# Author: ProgramZmh
# License: Apache-2.0
# Description: Dockerfile for chatnio

# Stage 1: Backend build with cross-compilation
FROM --platform=$BUILDPLATFORM golang:1.21-alpine AS backend

WORKDIR /backend
COPY . .

ARG TARGETARCH
ENV GOOS=linux \
    GOARCH=${TARGETARCH} \
    CGO_ENABLED=1 \
    CC=/usr/local/cross-toolchain/bin/aarch64-linux-musl-gcc \
    CXX=/usr/local/cross-toolchain/bin/aarch64-linux-musl-g++ \
    PKG_CONFIG_PATH=/usr/local/cross-toolchain/aarch64-linux-musl/lib/pkgconfig \
    CGO_CFLAGS="-I/usr/local/cross-toolchain/aarch64-linux-musl/include" \
    CGO_LDFLAGS="-L/usr/local/cross-toolchain/aarch64-linux-musl/lib -static"

# 安装核心依赖（新增关键包）
RUN apk add --no-cache \
    build-base \
    git \
    zlib-dev zlib-static \
    libressl-dev libressl-static \
    pkgconf \
    linux-headers \
    automake autoconf libtool file

# 安装ARM64交叉工具链（修复路径与校验）
RUN if [ "${TARGETARCH}" = "arm64" ]; then \
    mkdir -p /usr/local/cross-toolchain && \
    wget -q -O /tmp/cross.tgz https://musl.cc/aarch64-linux-musl-cross.tgz && \
    (echo "c909817856d6ceda86aa510894fa3527eac7989f0ef6e87b5721c58737a06c38  /tmp/cross.tgz" | sha256sum -c - || \
     { echo "工具链校验失败！当前哈希值：$(sha256sum /tmp/cross.tgz)"; exit 1; }) && \
    tar -xzf /tmp/cross.tgz -C /usr/local/cross-toolchain --strip-components=1 && \
    ln -sv /usr/local/cross-toolchain/bin/aarch64-linux-musl-* /usr/local/bin/ && \
    rm /tmp/cross.tgz; \
fi

# 编译命令（修复参数顺序）
RUN --mount=type=cache,target=/go/pkg/mod \
    if [ "${TARGETARCH}" = "arm64" ]; then \
        go build -v -x \
            -buildmode=pie \
            -tags="musl,netgo,static" \
            -ldflags='-linkmode=external -extldflags "-static-pie -lz -lpthread"' \
            -o chat .; \
    else \
        CGO_ENABLED=0 \
        go build -v \
            -tags=netgo \
            -ldflags="-s -w" \
            -o chat .; \
    fi
# Stage 2: Frontend build
FROM node:18-alpine AS frontend

WORKDIR /app
COPY ./app .

RUN npm install -g pnpm && \
    pnpm install && \
    pnpm run build && \
    rm -rf node_modules src

# Stage 3: Final image
FROM alpine:3.19


RUN apk upgrade --no-cache && \
    apk add --no-cache ca-certificates tzdata && \
    echo "Asia/Shanghai" > /etc/timezone && \
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

WORKDIR /


COPY --from=backend /backend/chat /chat
COPY --from=backend /backend/config.example.yaml /config.example.yaml
COPY --from=backend /backend/utils/templates /utils/templates
COPY --from=backend /backend/addition/article/template.docx /addition/article/template.docx
COPY --from=frontend /app/dist /app/dist

VOLUME ["/config", "/logs", "/storage"]
EXPOSE 8094

ENTRYPOINT ["/chat"]
