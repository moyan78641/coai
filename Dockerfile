# Author: ProgramZmh
# License: Apache-2.0
# Description: Dockerfile for chatnio

# Stage 1: Backend build with cross-compilation
FROM --platform=$BUILDPLATFORM golang:1.21-alpine AS backend

WORKDIR /backend
COPY . .

# 设置国内镜像源（如需）
# RUN go env -w GOPROXY=https://goproxy.cn,direct

ARG TARGETARCH
ARG TARGETOS
ENV GOOS=$TARGETOS \
    GOARCH=$TARGETARCH \
    CGO_ENABLED=1 \
    GO111MODULE=on

# 安装跨平台编译工具链（关键修复）
RUN apk add --no-cache build-base git && \
    if [ "$TARGETARCH" = "arm64" ]; then \
      wget -q -O /tmp/cross.tgz https://musl.cc/aarch64-linux-musl-cross.tgz && \
      tar -xzf /tmp/cross.tgz -C /usr/local && \
      rm /tmp/cross.tgz; \
    fi

# 统一构建命令（关键修改）
RUN if [ "$TARGETARCH" = "arm64" ]; then \
      CC=/usr/local/aarch64-linux-musl-cross/bin/aarch64-linux-musl-gcc \
      CXX=/usr/local/aarch64-linux-musl-cross/bin/aarch64-linux-musl-g++ \
      GOARCH=arm64 \
      go build -v -trimpath -ldflags="-s -w -extldflags=-static" -tags=musl -o chat .; \
    else \
      CGO_ENABLED=0 \
      go build -v -trimpath -ldflags="-s -w" -o chat .; \
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
