# Author: ProgramZmh
# License: Apache-2.0
# Description: Dockerfile for chatnio

# Stage 1: Backend build with cross-compilation
FROM --platform=$BUILDPLATFORM golang:1.21-alpine AS backend

WORKDIR /backend
COPY . .

ARG TARGETARCH
ARG TARGETOS
ENV GOOS=$TARGETOS \
    GOARCH=$TARGETARCH \
    CGO_ENABLED=1 \
    GO111MODULE=on \
    GOPROXY=https://goproxy.cn,direct  # 强制使用国内镜像

# 安装完整编译工具链（关键修复）
RUN apk add --no-cache build-base git zlib-dev zlib-static linux-headers

# 安装并配置ARM64交叉编译器
RUN if [ "$TARGETARCH" = "arm64" ]; then \
      wget -q -O /tmp/cross.tgz https://musl.cc/aarch64-linux-musl-cross.tgz && \
      tar -xzf /tmp/cross.tgz -C /usr/local && \
      ln -s /usr/local/aarch64-linux-musl-cross/lib/libc.so /lib/libc.musl-aarch64.so.1 && \
      rm /tmp/cross.tgz; \
    fi

# 带调试信息的构建命令
RUN --mount=type=cache,target=/go/pkg/mod \
    if [ "$TARGETARCH" = "arm64" ]; then \
      CC=/usr/local/aarch64-linux-musl-cross/bin/aarch64-linux-musl-gcc \
      CXX=/usr/local/aarch64-linux-musl-cross/bin/aarch64-linux-musl-g++ \
      GOARCH=arm64 \
      go build -v -x -trimpath \
        -ldflags="-s -w -extldflags='-static -L/usr/local/aarch64-linux-musl-cross/aarch64-linux-musl/lib'" \
        -tags="musl netgo" \
        -o chat .; \
    else \
      CGO_ENABLED=0 \
      go build -v -trimpath -ldflags="-s -w" -tags="netgo" -o chat .; \
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

# 基础配置优化
RUN apk upgrade --no-cache && \
    apk add --no-cache ca-certificates tzdata && \
    echo "Asia/Shanghai" > /etc/timezone && \
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

WORKDIR /

# 复制构建产物
COPY --from=backend /backend/chat /chat
COPY --from=backend /backend/config.example.yaml /config.example.yaml
COPY --from=backend /backend/utils/templates /utils/templates
COPY --from=backend /backend/addition/article/template.docx /addition/article/template.docx
COPY --from=frontend /app/dist /app/dist

VOLUME ["/config", "/logs", "/storage"]
EXPOSE 8094

ENTRYPOINT ["/chat"]
