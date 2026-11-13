# sheeridVerify —— 容器化运行环境
#
# 分层思路：
#   base  系统依赖（Camoufox/Firefox 运行库 + Xvfb + noVNC）
#   deps  npm 依赖，独立成层便于复用缓存
#   app   源码 + 浏览器二进制
FROM node:22-bookworm-slim AS base

# 官方 deb.debian.org 在国内访问慢，换阿里云镜像；可用 --build-arg 覆盖
ARG DEBIAN_MIRROR=mirrors.aliyun.com
RUN sed -i "s|deb.debian.org|${DEBIAN_MIRROR}|g; s|security.debian.org|${DEBIAN_MIRROR}|g" \
      /etc/apt/sources.list.d/debian.sources 2>/dev/null \
    || sed -i "s|deb.debian.org|${DEBIAN_MIRROR}|g; s|security.debian.org|${DEBIAN_MIRROR}|g" /etc/apt/sources.list

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    DISPLAY=:99

# Camoufox 基于 Firefox，运行库与 Playwright 的 firefox 依赖集一致；
# Xvfb/x11vnc/noVNC 让容器内的「有界面浏览器」可被外部看到并手动操作
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl unzip tini procps \
      libasound2 libatk-bridge2.0-0 libatk1.0-0 libatspi2.0-0 \
      libcairo2 libcups2 libdbus-1-3 libdbus-glib-1-2 libdrm2 \
      libgbm1 libglib2.0-0 libgtk-3-0 libnspr4 libnss3 libpango-1.0-0 \
      libx11-6 libx11-6 libx11-xcb1 libxcb1 libxcb-shm0 libxcomposite1 libxdamage1 \
      libxext6 libxfixes3 libxkbcommon0 libxrandr2 libxt6 libxtst6 \
      libpangocairo-1.0-0 libxrender1 \
      fonts-noto-cjk fonts-noto-color-emoji fonts-liberation \
      xvfb x11vnc novnc websockify \
 && rm -rf /var/lib/apt/lists/*

FROM base AS deps
WORKDIR /app
# 只复制依赖清单，源码改动不触发依赖重装
COPY package.json package-lock.json ./
RUN npm ci

FROM base AS app
WORKDIR /app

COPY --from=deps /app/node_modules ./node_modules
COPY . .

# Camoufox 浏览器二进制。
# 用构建前预下载的 zip（docker/cache/），而不是联网 `npm run browser:install`：
# 后者拉 GitHub Releases 单个 1.3GB 文件，国内在 97% 处反复断连且不续传。
# 缓存中没有 zip 时自动回退到在线安装。
COPY docker/install-browser.sh /usr/local/bin/install-browser.sh
RUN chmod +x /usr/local/bin/install-browser.sh \
 && if [ -f docker/cache/camoufox-lin.arm64.zip ]; then \
      /usr/local/bin/install-browser.sh docker/cache/camoufox-lin.arm64.zip; \
    else \
      npm run browser:install; \
    fi

COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh \
 && mkdir -p /app/config /app/.runs /app/documents /app/download

# 8787 = 工作台；6080 = noVNC 桌面
EXPOSE 8787 6080

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["web"]
