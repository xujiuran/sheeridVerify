#!/bin/sh
# 解压预置的 Camoufox 浏览器包到 camoufox 的安装目录。
#
# 为什么不用 `npm run browser:install`：它从 GitHub Releases 拉 1.3GB 单文件，
# 国内网络在 97% 处反复断连，且自带下载器不支持续传。构建前用 curl -C - 把 zip
# 下到 docker/cache/，构建时只做本地解压。
#
# 目录结构须与 camoufox 的 multiversion.js 一致：
#   $INSTALL_DIR/browsers/<repo>/<version>-<build>/version.json
#   $INSTALL_DIR/config.json  -> {"active_version": "browsers/<repo>/<version>-<build>"}
#   $INSTALL_DIR/.0.5_FLAG    -> 兼容标记，缺失会触发「清理旧数据」把浏览器删掉
set -eu

ZIP="${1:-}"
INSTALL_DIR="${CAMOUFOX_HOME:-$HOME/.cache/camoufox}"
REPO_NAME="Official"
VERSION="${BROWSER_VERSION:-158.0.1}"
BUILD="${BROWSER_BUILD:-beta.41}"
INTERFACE="${BROWSER_INTERFACE:-1}"

if [ -z "$ZIP" ] || [ ! -f "$ZIP" ]; then
  printf '[browser] 未提供压缩包（%s），回退在线安装\n' "${ZIP:-<empty>}" >&2
  exec npm run browser:install
fi

FOLDER="${VERSION}-${BUILD}"
DEST="${INSTALL_DIR}/browsers/${REPO_NAME}/${FOLDER}"

printf '[browser] 解压 -> %s\n' "$DEST"
rm -rf "$INSTALL_DIR"
mkdir -p "$DEST"
unzip -q "$ZIP" -d "$DEST"

# camoufox 靠 version.json 识别已安装构建；build 字段必须与 browser-pin.json 一致
cat > "${DEST}/version.json" <<EOF
{"version":"${VERSION}","build":"${BUILD}","prerelease":false,"interface":${INTERFACE}}
EOF

# 标记当前活动版本，避免启动时再去 GitHub 查询
cat > "${INSTALL_DIR}/config.json" <<EOF
{"active_version":"browsers/${REPO_NAME}/${FOLDER}"}
EOF

# 兼容标记：缺少它会让 resolveInstalledPath 认为旧数据不兼容并删除整个目录
: > "${INSTALL_DIR}/.0.5_FLAG"

# 二进制需要可执行位
chmod +x "${DEST}/camoufox-bin" 2>/dev/null || true

printf '[browser] 完成：\n'
ls -1 "$INSTALL_DIR"
ls -1 "$DEST" | head -5
