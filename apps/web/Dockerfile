# Build context: the repository root.
ARG NODE_IMAGE=node:26.12.0-slim
ARG NGINX_IMAGE=nginx:1.30-alpine

FROM ${NODE_IMAGE} AS build

# The root `prepare` script runs husky, which needs a git checkout.
ENV HUSKY=0
RUN npm install --global pnpm@12.14.0

WORKDIR /app
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY apps/web/package.json apps/web/
COPY packages/api-client/package.json packages/api-client/
COPY scripts/check-package-manager.cjs scripts/
RUN pnpm install --frozen-lockfile --filter @atlas/web...

COPY apps/web apps/web
COPY packages/api-client packages/api-client
RUN pnpm --filter @atlas/web run build

FROM ${NGINX_IMAGE}

# The image renders templates at start, and replaces only NGINX_* variables.
ENV NGINX_ENVSUBST_FILTER=^NGINX_
COPY apps/web/default.conf.template /etc/nginx/templates/default.conf.template
COPY --from=build /app/apps/web/dist/client /usr/share/nginx/html

EXPOSE 80
HEALTHCHECK --interval=15s --timeout=5s --start-period=5s --retries=5 \
  CMD wget -q -O /dev/null http://127.0.0.1/ || exit 1
