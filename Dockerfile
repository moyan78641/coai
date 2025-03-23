# Author: ProgramZmh
# License: Apache-2.0
# Description: Dockerfile for chatnio

# Stage 1: Backend build with cross-compilation
FROM --platform=$BUILDPLATFORM golang:1.21-alpine AS backend

WORKDIR /backend
COPY . .

ARG TARGETARCH
ARG TARGETOS
ENV GOOS=${TARGETOS} \
    GOARCH=${TARGETARCH} \
    CGO_ENABLED=1 \
    GO111MODULE=on \
    GOPROXY=https://goproxy.cn,direct \
    # 关键修复：设置完整工具链路径
    PATH="/usr/local/aarch64-linux-musl-cross/bin:${PATH}"

# 安装完整依赖（新增关键包）
RUN apk add --no-cache build-base git zlib-dev zlib-static linux-headers libc6-compat

# 更新后的工具链安装步骤
RUN if [ "${TARGETARCH}" = "arm64" ]; then \
    mkdir -p /usr/local/cross-toolchain && \
    # 使用HTTPS镜像源（带重试机制）
    wget -q --tries=3 --timeout=30 --retry-connrefused \
        -O /tmp/cross.tgz \
        https://musl.cc/aarch64-linux-musl-cross.tgz && \
    # 应用您验证的SHA256 (c9098178...)
    (echo "c909817856d6ceda86aa510894fa3527eac7989f0ef6e87b5721c58737a06c38  /tmp/cross.tgz" | sha256sum -c -) && \
    # 解压到专用目录（保持路径一致性）
    tar -xzf /tmp/cross.tgz -C /usr/local/cross-toolchain --strip-components=1 && \
    # 创建标准符号链接
    ln -sv /usr/local/cross-toolchain/bin/* /usr/local/bin/ && \
    # 验证关键文件存在性
    test -x /usr/local/bin/aarch64-linux-musl-gcc && \
    # 清理临时文件
    rm -vf /tmp/cross.tgz; \
    # 显示工具链版本
    aarch64-linux-musl-gcc --version | head -n1; \
fi

# 预下载Go模块（加速构建）
RUN go mod download

# 修复编译命令
RUN --mount=type=cache,target=/go/pkg/mod \
    if [ "${TARGETARCH}" = "arm64" ]; then \
        CC=aarch64-linux-musl-gcc \
        CXX=aarch64-linux-musl-g++ \
        GOARM=7 \
        CGO_CFLAGS="-I/usr/local/aarch64-linux-musl-cross/aarch64-linux-musl/include" \
        CGO_LDFLAGS="-L/usr/local/aarch64-linux-musl-cross/aarch64-linux-musl/lib" \
        go build -v -x \
            -buildmode=pie \
            -ldflags="-linkmode=external -extldflags '-static -lz -lpthread'" \
            -tags="musl,netgo" \
            -o chat .; \
    else \
        CGO_ENABLED=0 \
        go build -v \
            -ldflags="-s -w" \
            -tags="netgo" \
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
