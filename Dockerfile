# Author: ProgramZmh
# License: Apache-2.0
# Description: Dockerfile for chatnio

# Stage 1: Backend build with cross-compilation
FROM --platform=$BUILDPLATFORM golang:1.21-alpine3.18 AS backend
WORKDIR /backend
COPY . .

# Ensure xunhupay module is properly included
RUN mkdir -p /go/src/xunhupay && cp -r xunhupay-master/* /go/src/xunhupay/

ARG TARGETARCH
ENV GOOS=linux \
    GOARCH=${TARGETARCH} \
    CGO_ENABLED=1

# 修复证书和镜像源
RUN apk add --no-cache --update-ca-certificates && \
    echo -e "https://mirrors.tuna.tsinghua.edu.cn/alpine/v3.18/main\n\
    https://mirrors.tuna.tsinghua.edu.cn/alpine/v3.18/community" > /etc/apk/repositories

# 分阶段安装依赖
RUN set -ex; \
    apk update --no-cache; \
    apk add --no-cache --virtual .build-deps-stage1 \
        build-base git linux-headers automake autoconf; \
    apk add --no-cache --virtual .build-deps-stage2 \
        openssl-dev openssl-static; \
    apk add --no-cache --virtual .build-deps-stage3 \
        zlib-dev zlib-static pkgconf libtool file; \
    if [ "${TARGETARCH}" = "amd64" ]; then \
        apk add --no-cache --virtual .build-deps-stage4 \
            upx; \
    fi; \
    ls -l /usr/lib/libssl.a && \
    if [ -x "$(command -v upx)" ]; then upx --version; fi

# ARM64交叉工具链
RUN if [ "${TARGETARCH}" = "arm64" ]; then \
    mkdir -p /usr/local/cross-toolchain && \
    wget -q -O /tmp/cross.tgz https://more.musl.cc/11.2.1/x86_64-linux-musl/aarch64-linux-musl-cross.tgz && \
    (echo "0d7b2f6d3d722a2b571f2f1c5e0f66a6a4d3d8d0c0a5c5c6d9b9d6a5c8f4a9e  /tmp/cross.tgz" | sha256sum -c -) && \
    tar -xzf /tmp/cross.tgz -C /usr/local/cross-toolchain --strip-components=1 && \
    ln -sv /usr/local/cross-toolchain/bin/aarch64-linux-musl-* /usr/local/bin/ && \
    rm /tmp/cross.tgz; \
fi

# 编译
RUN --mount=type=cache,target=/go/pkg/mod \
    if [ "${TARGETARCH}" = "arm64" ]; then \
        CC=aarch64-linux-musl-gcc CXX=aarch64-linux-musl-g++ \
        GOARM=7 \
        CGO_CFLAGS="-I/usr/local/cross-toolchain/aarch64-linux-musl/include" \
        CGO_LDFLAGS="-L/usr/local/cross-toolchain/aarch64-linux-musl/lib -static" \
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
