#!/bin/bash
# frps 服务端自动安装、配置与自启动脚本
# 从 https://github.com/fatedier/frp/releases 下载并安装 frps，交互式配置，systemd 自启

set -e

FRP_GITHUB_REPO="fatedier/frp"
FRP_VERSION_FALLBACK="v0.67.0"
INSTALL_BIN="/usr/local/bin/frps"
CONFIG_DIR="/etc/frp"
CONFIG_FILE="${CONFIG_DIR}/frps.toml"
SYSTEMD_UNIT="/etc/systemd/system/frps.service"

die() { echo "[ERROR] $*" >&2; exit 1; }
info() { echo "[INFO] $*" >&2; }

# ---- 1. 前置检查与环境 ----
check_root() {
  if [ "$(id -u)" -ne 0 ]; then
    die "请使用 root 运行此脚本，或使用: sudo $0"
  fi
}

check_linux() {
  local os
  os="$(uname -s)"
  if [ "$os" != "Linux" ]; then
    die "此脚本仅支持 Linux，当前系统: $os"
  fi
}

check_deps() {
  if command -v curl &>/dev/null; then
    DOWNLOAD_CMD="curl"
  elif command -v wget &>/dev/null; then
    DOWNLOAD_CMD="wget"
  else
    die "需要 curl 或 wget，请先安装其一"
  fi
  command -v tar &>/dev/null || die "需要 tar，请先安装"
}

# 安装前检测配置文件是否已存在，询问是否覆盖
check_config_overwrite() {
  SKIP_WRITE_CONFIG=0
  if [ -f "$CONFIG_FILE" ]; then
    echo -n "配置文件 $CONFIG_FILE 已存在，是否覆盖? [y/N] "
    read -r ans
    case "$ans" in
      [yY]|[yY][eE][sS]) ;;
      *)
        SKIP_WRITE_CONFIG=1
        info "不覆盖配置，将仅更新 frps 二进制与 systemd 服务"
        ;;
    esac
  fi
}

# ---- 2. 架构与版本 ----
get_arch() {
  local m
  m="$(uname -m)"
  case "$m" in
    x86_64)   echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    armv7l|arm)   echo "arm" ;;
    *) die "不支持的架构: $m" ;;
  esac
}

get_latest_version() {
  local tag
  # 优先用 jq 解析 GitHub API
  if command -v jq &>/dev/null; then
    tag=$(curl -sSL "https://api.github.com/repos/${FRP_GITHUB_REPO}/releases/latest" | jq -r '.tag_name // empty')
  fi
  # 无 jq 或 API 失败时：跟随 releases/latest 重定向，从 Location 提取 tag
  if [ -z "$tag" ]; then
    tag=$(curl -sI "https://github.com/${FRP_GITHUB_REPO}/releases/latest" 2>/dev/null | sed -n 's|^[Ll]ocation:.*/releases/tag/\(v[^[:space:]]*\).*|\1|p' | tr -d '\r')
  fi
  if [ -z "$tag" ]; then
    tag="$FRP_VERSION_FALLBACK"
    info "使用内置版本: $tag（网络不可达时）"
  else
    info "最新版本: $tag"
  fi
  echo "$tag"
}

download_and_install_binary() {
  local tag version arch url tmpdir
  tag="$1"
  version="${tag#v}"
  arch="$2"
  url="https://github.com/${FRP_GITHUB_REPO}/releases/download/${tag}/frp_${version}_linux_${arch}.tar.gz"

  if [ -f "$INSTALL_BIN" ]; then
    echo -n "已存在 $INSTALL_BIN，是否覆盖? [y/N] "
    read -r ans
    case "$ans" in
      [yY]|[yY][eE][sS]) ;;
      *) die "用户取消覆盖，退出" ;;
    esac
  fi

  tmpdir="$(mktemp -d)"
  trap "rm -rf '$tmpdir'" EXIT

  info "下载: $url"
  if [ "$DOWNLOAD_CMD" = "curl" ]; then
    curl -sSL -o "${tmpdir}/frp.tar.gz" "$url"
  else
    wget -q -O "${tmpdir}/frp.tar.gz" "$url"
  fi

  tar -xzf "${tmpdir}/frp.tar.gz" -C "$tmpdir"
  local extracted
  extracted="$(find "$tmpdir" -maxdepth 1 -type d -name 'frp_*' | head -1)"
  [ -n "$extracted" ] || die "解压后未找到 frp_* 目录"
  [ -f "${extracted}/frps" ] || die "解压包中未找到 frps"

  mkdir -p "$(dirname "$INSTALL_BIN")"
  cp "${extracted}/frps" "$INSTALL_BIN"
  chmod +x "$INSTALL_BIN"
  info "已安装: $INSTALL_BIN"
}

# ---- 3. 交互式参数收集 ----
read_required() {
  local bindPort vhostHTTPPort auth_method auth_token

  echo ""
  echo "========== 必填参数 =========="

  while true; do
    read -rp "bindPort (frpc 连接端口，如 7000): " bindPort
    if [ -n "$bindPort" ] && [[ "$bindPort" =~ ^[0-9]+$ ]]; then
      break
    fi
    echo "请输入有效端口数字"
  done

  while true; do
    read -rp "vhostHTTPPort (HTTP 代理监听端口): " vhostHTTPPort
    if [ -n "$vhostHTTPPort" ] && [[ "$vhostHTTPPort" =~ ^[0-9]+$ ]]; then
      break
    fi
    echo "请输入有效端口数字"
  done

  read -rp "auth.method [默认 token，直接回车使用]: " auth_method
  auth_method="${auth_method:-token}"

  while true; do
    read -rp "auth.token (与客户端一致): " auth_token
    if [ -n "$auth_token" ]; then
      break
    fi
    echo "token 不能为空"
  done

  BIND_PORT="$bindPort"
  VHOST_HTTP_PORT="$vhostHTTPPort"
  AUTH_METHOD="$auth_method"
  AUTH_TOKEN="$auth_token"
}

read_optional() {
  local ws_port ws_addr ws_user ws_pass

  echo ""
  echo "========== 可选参数（回车跳过） =========="

  read -rp "webServer.port (Dashboard 端口，不填则不启用): " ws_port
  WEB_PORT="$ws_port"

  if [ -n "$WEB_PORT" ] && [[ "$WEB_PORT" =~ ^[0-9]+$ ]]; then
    read -rp "webServer.addr [默认 0.0.0.0]: " ws_addr
    WEB_ADDR="${ws_addr:-0.0.0.0}"
    read -rp "webServer.user (BasicAuth 用户名) [默认 admin]: " ws_user
    WEB_USER="${ws_user:-admin}"
    read -rsp "webServer.password (BasicAuth 密码) [默认 admin]: " ws_pass
    echo ""
    WEB_PASS="${ws_pass:-admin}"
  else
    WEB_ADDR="0.0.0.0"
    WEB_USER="admin"
    WEB_PASS="admin"
  fi
}

# ---- 4. 生成 frps.toml ----
write_config() {
  if [ "$SKIP_WRITE_CONFIG" = "1" ]; then
    info "保留现有配置文件: $CONFIG_FILE"
    return
  fi
  mkdir -p "$CONFIG_DIR"

  cat > "$CONFIG_FILE" << EOF
# frps 配置 - 由 install-frps.sh 生成
bindPort = ${BIND_PORT}
vhostHTTPPort = ${VHOST_HTTP_PORT}

[auth]
method = "${AUTH_METHOD}"
token = "${AUTH_TOKEN}"
EOF

  if [ -n "$WEB_PORT" ] && [[ "$WEB_PORT" =~ ^[0-9]+$ ]]; then
    cat >> "$CONFIG_FILE" << EOF

[webServer]
addr = "${WEB_ADDR}"
port = ${WEB_PORT}
EOF
    [ -n "$WEB_USER" ] && echo "user = \"${WEB_USER}\"" >> "$CONFIG_FILE"
    [ -n "$WEB_PASS" ] && echo "password = \"${WEB_PASS}\"" >> "$CONFIG_FILE"
  fi

  info "配置已写入: $CONFIG_FILE"
}

# ---- 5. systemd 服务与自启动 ----
install_systemd() {
  cat > "$SYSTEMD_UNIT" << 'UNIT'
[Unit]
Description=frp server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/frps -c /etc/frp/frps.toml
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
UNIT

  systemctl daemon-reload
  systemctl enable frps
  systemctl start frps
  info "systemd 服务已启用并启动: frps"
}

# ---- 6. 收尾输出 ----
print_summary() {
  echo ""
  echo "========== 安装完成 =========="
  echo "  配置文件: $CONFIG_FILE"
  echo "  服务名称: frps"
  echo "  常用命令:"
  echo "    systemctl status frps   # 状态"
  echo "    systemctl restart frps  # 重启"
  echo "    systemctl stop frps    # 停止"
  echo "    journalctl -u frps -f   # 日志"
  if [ -z "$WEB_PORT" ] || ! [[ "$WEB_PORT" =~ ^[0-9]+$ ]]; then
    echo ""
    echo "  未配置 Dashboard。若需启用，请编辑 $CONFIG_FILE 添加 [webServer] 段后执行: systemctl restart frps"
  fi
  echo ""
}

# ---- main ----
main() {
  check_root
  check_linux
  check_deps
  check_config_overwrite

  arch="$(get_arch)"
  tag="$(get_latest_version)"
  download_and_install_binary "$tag" "$arch"

  if [ "$SKIP_WRITE_CONFIG" != "1" ]; then
    read_required
    read_optional
  fi
  write_config
  install_systemd
  print_summary
}

main "$@"
