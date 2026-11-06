# Build context: repository root. Dockerfile.dockerignore takes precedence over
# .dockerignore for this image; the standalone API/web Dockerfiles are unchanged.
ARG NODE_IMAGE=node:26.12.0-slim
ARG BUILDER_IMAGE=hexpm/elixir:1.20.4-erlang-29.1.2-debian-trixie-20261020-slim
ARG RUNTIME_IMAGE=debian:trixie-slim

FROM ${NODE_IMAGE} AS frontend

ENV HUSKY=0
RUN npm install --global pnpm@12.14.0
WORKDIR /app
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY apps/web/package.json apps/web/
COPY packages/api-client/package.json packages/api-client/
COPY scripts/check-package-manager.cjs scripts/
# Fail rather than silently build with a pnpm different from the repository pin.
RUN node -e 'if (require("./package.json").packageManager !== "pnpm@12.14.0") process.exit(1)' \
  && pnpm install --frozen-lockfile --filter @atlas/web...
COPY apps/web apps/web
COPY packages/api-client packages/api-client
RUN pnpm --filter @atlas/web run build

FROM ${BUILDER_IMAGE} AS build

RUN apt-get update -y \
  && apt-get install -y --no-install-recommends build-essential git ca-certificates curl \
  && rm -rf /var/lib/apt/lists/*
WORKDIR /app
ENV MIX_ENV=prod
RUN mix local.hex --force && mix local.rebar --force
COPY apps/api/mix.exs apps/api/mix.lock ./
RUN mix deps.get --only prod

# Erlang's httpc rejects GitHub's large redirect headers, so rustler_precompiled (y_ex) and
# elixir_make (vix) cannot download their precompiled NIFs. Pre-seed their caches with curl.
# Both still check each file against the checksum shipped in the Hex package.
# The NIF versions (y_ex 2.15, vix 2.17) are the newest each package publishes for OTP 29.
ENV RUSTLER_PRECOMPILED_GLOBAL_CACHE_PATH=/opt/rustler_precompiled \
  ELIXIR_MAKE_CACHE_DIR=/opt/elixir_make
RUN version=$(sed -n 's/^  "y_ex": {:hex, :y_ex, "\([^"]*\)".*/\1/p' mix.lock) \
  && test -n "$version" \
  && file=libyex-v${version}-nif-2.15-$(uname -m)-unknown-linux-gnu.so.tar.gz \
  && mkdir -p "$RUSTLER_PRECOMPILED_GLOBAL_CACHE_PATH" \
  && curl -fsSL --retry 3 -o "$RUSTLER_PRECOMPILED_GLOBAL_CACHE_PATH/$file" \
    "https://github.com/satoren/y_ex/releases/download/v${version}/$file"
RUN version=$(sed -n 's/^  "vix": {:hex, :vix, "\([^"]*\)".*/\1/p' mix.lock) \
  && test -n "$version" \
  && file=vix-nif-2.17-$(uname -m)-linux-gnu-${version}.tar.gz \
  && mkdir -p "$ELIXIR_MAKE_CACHE_DIR" \
  && curl -fsSL --retry 3 -o "$ELIXIR_MAKE_CACHE_DIR/$file" \
    "https://github.com/akash-akya/vix/releases/download/v${version}/$file"

RUN mkdir config
COPY apps/api/config/config.exs apps/api/config/prod.exs config/
RUN mix deps.compile
COPY apps/api/priv priv
COPY apps/api/lib lib
RUN mix compile
# Bake this image's HTML and assets into the release, never into the shared store.
COPY --from=frontend /app/apps/web/dist/client/ priv/static/
RUN test -s priv/static/index.html && test -d priv/static/assets
# Source checkout permissions must not make runtime config unreadable to UID 1000.
COPY --chmod=0644 apps/api/config/runtime.exs config/
RUN mix release && chmod -R a+rX,go-w _build/prod/rel/atlas

FROM ${RUNTIME_IMAGE}

RUN apt-get update -y \
  && apt-get install -y --no-install-recommends libstdc++6 openssl libncurses6 ca-certificates curl \
    bash coreutils findutils util-linux \
  && rm -rf /var/lib/apt/lists/* \
  && useradd --system --uid 1000 --user-group atlas \
  && install -d -o atlas -g atlas -m 0755 /var/lib/atlas/frontend-assets

# The build and release remain root-owned; only /tmp and the optional asset store
# are writable by atlas. Set FRONTEND_ASSET_DIR to the mounted retention directory.
ENV LANG=C.UTF-8 PHX_SERVER=true RELEASE_TMP=/tmp SERVE_FRONTEND=true PORT=4000
WORKDIR /app
COPY --from=build --chown=0:0 /app/_build/prod/rel/atlas ./
COPY --chmod=0755 deploy/entrypoint deploy/publish-assets ./deploy/
USER atlas

EXPOSE 4000
# Loopback is exempt from force_ssl; health checks need no forwarded headers.
HEALTHCHECK --interval=15s --timeout=5s --start-period=30s --retries=5 \
  CMD curl -fsS http://127.0.0.1:4000/health || exit 1

ENTRYPOINT ["/app/deploy/entrypoint"]
