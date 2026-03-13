# SPDX-License-Identifier: PMPL-1.0-or-later
# Glyphbase Docker Image
# Multi-stage build for minimal final image

# Stage 1: Build UI
FROM docker.io/denoland/deno:2.1.4 AS ui-builder

WORKDIR /build/ui

# Copy UI dependencies
COPY ui/deno.json ui/deno.lock ./
COPY ui/package.json ui/rescript.json ./

# Install dependencies
RUN deno cache deno.json

# Copy UI source
COPY ui/ .

# Build UI
RUN deno task build

# Stage 2: Build Server
FROM docker.io/hexpm/gleam:1.7.1-erlang-27.2.1 AS server-builder

WORKDIR /build/server

# Copy server dependencies
COPY server/gleam.toml server/manifest.toml* ./

# Download dependencies
RUN gleam deps download

# Copy server source
COPY server/src ./src
COPY server/test ./test

# Build server
RUN gleam build --target erlang

# Stage 3: Runtime
FROM docker.io/hexpm/erlang:27.2.1-alpine

WORKDIR /app

# Install runtime dependencies
RUN apk add --no-cache libstdc++ openssl

# Copy built server from builder
COPY --from=server-builder /build/server/build /app/build

# Copy built UI from builder
COPY --from=ui-builder /build/ui/dist /app/public

# Create data directory
RUN mkdir -p /data && chmod 777 /data

# Environment variables
ENV PORT=4000
ENV DATABASE_PATH=/data
ENV GLEAM_ERLANG_PATH=/app/build

# Expose port
EXPOSE 4000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:4000/health || exit 1

# Run server
CMD ["gleam", "run"]
