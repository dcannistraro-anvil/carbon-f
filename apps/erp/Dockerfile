FROM node:22 AS deps
WORKDIR /repo
RUN corepack enable
# Copy root manifests for workspaces
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc turbo.json lingui.config.js ./
# Copy only what we need to install and build
COPY apps ./apps
COPY packages ./packages
COPY patches ./patches
# Install all workspaces (dev deps are needed to build)
RUN pnpm install --frozen-lockfile

FROM deps AS build
ARG NODE_OPTIONS
ENV NODE_OPTIONS="--max-old-space-size=8024"
# Build only ERP and its deps
RUN pnpm run build:erp

FROM node:22-slim
WORKDIR /repo
ENV COREPACK_ENABLE_DOWNLOAD_PROMPT=0
RUN corepack enable
ENV NODE_ENV=production
ENV PORT=3000
# Install curl for health checks
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*
# Production needs built app, node_modules, and packages (for workspace deps)
COPY --from=deps /repo/node_modules ./node_modules
COPY --from=deps /repo/packages ./packages
COPY --from=build /repo/apps/erp ./apps/erp
EXPOSE 3000
WORKDIR /repo/apps/erp
CMD ["pnpm","run","start"]
