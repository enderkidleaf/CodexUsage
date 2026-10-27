#!/bin/bash
# 构建 CodexUsage.app（菜单栏 Codex 用量控件）
# 用法：
#   ./build.sh           构建到 build/CodexUsage.app
#   ./build.sh install   构建并安装到 /Applications/CodexUsage.app
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SRC="$ROOT/Sources/CodexUsage"
BUILD="$ROOT/build"
APP="$BUILD/CodexUsage.app"
DEST="/Applications/CodexUsage.app"
BIN_NAME="CodexUsage"

build() {
  echo "==> 清理旧产物"
  rm -rf "$BUILD"
  mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

  echo "==> Swift 编译（release）"

  # 兼容部分 Command Line Tools 残留：include/swift 下同时存在
  # module.modulemap 与 bridging.modulemap 重复定义 SwiftBridging，
  # 用 VFS overlay 把旧 module.modulemap 遮蔽为空文件，无需改动系统目录。
  OVERLAY_FLAGS=()
  SWIFT_BIN_DIR="$(cd "$(dirname "$(xcrun -f swiftc)")" && pwd)"
  CLT_SWIFT_INCLUDE="$(cd "$SWIFT_BIN_DIR/../include/swift" 2>/dev/null && pwd || true)"
  if [ -n "$CLT_SWIFT_INCLUDE" ] \
     && [ -f "$CLT_SWIFT_INCLUDE/module.modulemap" ] \
     && [ -f "$CLT_SWIFT_INCLUDE/bridging.modulemap" ]; then
    echo "==> 检测到重复 modulemap，启用 VFS overlay 兼容"
    : > "$BUILD/empty.modulemap"
    cat > "$BUILD/clt-overlay.yaml" <<EOF
{
  "version": 0,
  "case-sensitive": "false",
  "roots": [
    {
      "type": "file",
      "name": "$CLT_SWIFT_INCLUDE/module.modulemap",
      "external-contents": "$BUILD/empty.modulemap"
    }
  ]
}
EOF
    OVERLAY_FLAGS=(-Xcc -ivfsoverlay -Xcc "$BUILD/clt-overlay.yaml")
  fi

  cd "$SRC"
  swiftc -O \
    "${OVERLAY_FLAGS[@]}" \
    -o "$APP/Contents/MacOS/$BIN_NAME" \
    *.swift

  echo "==> 组装 .app bundle"
  cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
  cp "$ROOT/Resources/AppIcon.png" "$APP/Contents/Resources/AppIcon.png"

  echo "==> Ad-hoc 代码签名"
  codesign --force --sign - "$APP"

  echo "==> 校验签名"
  codesign --verify --verbose "$APP"

  echo ""
  echo "构建完成：$APP"
  echo "运行：open \"$APP\""
  echo "安装到 /Applications：./build.sh install"
}

install_app() {
  if pgrep -f "$DEST/Contents/MacOS/$BIN_NAME" >/dev/null 2>&1 \
     || pgrep -f "$APP/Contents/MacOS/$BIN_NAME" >/dev/null 2>&1; then
    echo "错误：CodexUsage 正在运行，请先在菜单栏控件中点击“退出”，再执行安装。" >&2
    exit 1
  fi
  echo "==> 安装到 $DEST"
  rm -rf "$DEST"
  cp -R "$APP" "$DEST"
  codesign --force --sign - "$DEST"
  codesign --verify --verbose "$DEST"
  echo ""
  echo "安装完成：$DEST"
  echo "启动：open \"$DEST\""
}

case "${1:-build}" in
  build) build ;;
  install) build && install_app ;;
  *)
    echo "用法：./build.sh [build|install]" >&2
    exit 2
    ;;
esac
