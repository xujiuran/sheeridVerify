#!/bin/sh
# 容器入口：拉起虚拟显示器 → 启动上游工作台 → 启动对外反代。
# 任何一环退出都终止整个容器，避免「端口在监听但服务其实已死」。
set -eu

APP_PORT_INTERNAL="${APP_PORT:-8788}"
WEB_PASSWORD="${ONE_WEB_PASSWORD:-JenkinWoo}"
PROXY_PORT_EXTERNAL="${PROXY_PORT:-8787}"

log() { printf '[entrypoint] %s\n' "$*"; }

# 1) 虚拟显示器：有界面浏览器（browser.headless=false）需要它，否则 Camoufox 启动失败
XVFB_PID=""
if [ "${ENABLE_DISPLAY:-1}" = "1" ]; then
  log "启动 Xvfb :99 (1440x900x24)"
  Xvfb :99 -screen 0 1440x900x24 -nolisten tcp >/tmp/xvfb.log 2>&1 &
  XVFB_PID=$!
  sleep 1

  if [ "${ENABLE_VNC:-1}" = "1" ]; then
    log "启动 x11vnc :5900（无密码，仅容器网络内可见）"
    x11vnc -display :99 -forever -shared -nopw -rfbport 5900 -quiet >/tmp/x11vnc.log 2>&1 &
    log "启动 noVNC :6080"
    websockify --web=/usr/share/novnc 6080 localhost:5900 >/tmp/websockify.log 2>&1 &
    log "浏览器桌面入口：http://127.0.0.1:6080/vnc.html?autoconnect=1&resize=scale"
  fi
else
  export DISPLAY=
fi

# 2) 配置文件缺失时用示例初始化
if [ ! -f config/sheerid.local.json ]; then
  log "config/sheerid.local.json 不存在，从示例复制（需要编辑后重启）"
  cp config/sheerid.example.json config/sheerid.local.json
fi

# 3) 上游工作台：只监听容器内回环，密码来自环境变量
log "启动工作台 127.0.0.1:${APP_PORT_INTERNAL}"
ONE_WEB_HOST=127.0.0.1 \
ONE_WEB_PASSWORD="${WEB_PASSWORD}" \
  node src/web/server.js --port "${APP_PORT_INTERNAL}" &
APP_PID=$!

# 4) 对外反代：0.0.0.0:8787 -> 127.0.0.1:8788
#    上游只接受 Host 为 127.0.0.1:<port> 的请求（防 DNS rebinding），这里改写 Host
sleep 1
APP_PORT="${APP_PORT_INTERNAL}" PROXY_PORT="${PROXY_PORT_EXTERNAL}" node docker/local-proxy.js &
PROXY_PID=$!

log "工作台：http://127.0.0.1:${PROXY_PORT_EXTERNAL}  访问密码：${WEB_PASSWORD}"

cleanup() {
  log "收到退出信号，关闭子进程"
  kill "$APP_PID" "$PROXY_PID" ${XVFB_PID:+"$XVFB_PID"} 2>/dev/null || true
  wait 2>/dev/null || true
  exit 0
}
trap cleanup TERM INT

# 任一关键子进程退出即收尾
wait "$PROXY_PID" || true
cleanup
