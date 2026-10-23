ARG BUILDER_IMAGE=hexpm/elixir:1.20.4-erlang-29.1.2-debian-trixie-20261020-slim
ARG RUNTIME_IMAGE=debian:trixie-slim

FROM ${BUILDER_IMAGE} AS build

RUN apt-get update -y \
  && apt-get install -y --no-install-recommends build-essential git ca-certificates curl \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app
ENV MIX_ENV=prod
RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
RUN mix deps.get --only prod

# Erlang's httpc rejects GitHub's large redirect headers, so rustler_precompiled (y_ex) and
# elixir_make (vix) cannot download their precompiled NIFs. Pre-seed their caches with curl.
# Both still check each file against the checksum shipped in the Hex package.
# The NIF versions (y_ex 2.15, vix 2.17) are the newest each package publishes for OTP 29.
ENV RUSTLER_PRECOMPILED_GLOBAL_CACHE_PATH=/opt/rustler_precompiled \
  ELIXIR_MAKE_CACHE_DIR=/opt/elixir_make
RUN version=$(sed -n 's/^  "y_ex": {:hex, :y_ex, "\([^"]*\)".*/\1/p' mix.lock) \
  && file=libyex-v${version}-nif-2.15-$(uname -m)-unknown-linux-gnu.so.tar.gz \
  && mkdir -p "$RUSTLER_PRECOMPILED_GLOBAL_CACHE_PATH" \
  && curl -fsSL --retry 3 -o "$RUSTLER_PRECOMPILED_GLOBAL_CACHE_PATH/$file" \
    "https://github.com/satoren/y_ex/releases/download/v${version}/$file"
RUN version=$(sed -n 's/^  "vix": {:hex, :vix, "\([^"]*\)".*/\1/p' mix.lock) \
  && file=vix-nif-2.17-$(uname -m)-linux-gnu-${version}.tar.gz \
  && mkdir -p "$ELIXIR_MAKE_CACHE_DIR" \
  && curl -fsSL --retry 3 -o "$ELIXIR_MAKE_CACHE_DIR/$file" \
    "https://github.com/akash-akya/vix/releases/download/v${version}/$file"

RUN mkdir config
COPY config/config.exs config/prod.exs config/
RUN mix deps.compile

COPY priv priv
COPY lib lib
RUN mix compile

COPY config/runtime.exs config/
RUN mix release

FROM ${RUNTIME_IMAGE}

RUN apt-get update -y \
  && apt-get install -y --no-install-recommends libstdc++6 openssl libncurses6 ca-certificates curl \
  && rm -rf /var/lib/apt/lists/*

# The release directory stays root-owned and read-only; the release writes only to RELEASE_TMP.
ENV LANG=C.UTF-8 PHX_SERVER=true RELEASE_TMP=/tmp
WORKDIR /app
RUN useradd --system --uid 1000 atlas
COPY --from=build /app/_build/prod/rel/atlas ./
USER atlas

EXPOSE 4000
# 127.0.0.1 is exempt from force_ssl, so the check needs no forwarded headers.
HEALTHCHECK --interval=15s --timeout=5s --start-period=30s --retries=5 \
  CMD curl -fsS http://127.0.0.1:4000/health || exit 1

CMD ["sh", "-c", "bin/atlas eval 'Atlas.Release.migrate()' && exec bin/atlas start"]
