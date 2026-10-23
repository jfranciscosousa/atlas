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

# rustler_precompiled downloads the y_ex NIF with Erlang's httpc, which rejects GitHub's large
# redirect headers. Pre-seed its cache with curl; it still checks the file against y_ex's checksum.
# The NIF version is 2.15 because y_ex does not override rustler_precompiled's default.
ENV RUSTLER_PRECOMPILED_GLOBAL_CACHE_PATH=/opt/rustler_precompiled
RUN version=$(sed -n 's/.*:y_ex, "\([^"]*\)".*/\1/p' mix.lock) \
  && file=libyex-v${version}-nif-2.15-$(uname -m)-unknown-linux-gnu.so.tar.gz \
  && mkdir -p "$RUSTLER_PRECOMPILED_GLOBAL_CACHE_PATH" \
  && curl -fsSL --retry 3 -o "$RUSTLER_PRECOMPILED_GLOBAL_CACHE_PATH/$file" \
    "https://github.com/satoren/y_ex/releases/download/v${version}/$file"

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
