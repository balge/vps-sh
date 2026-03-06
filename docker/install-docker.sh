#!/bin/bash
# Docker 自动安装脚本，安装完成后按顺序交互式部署 portainer / lucky / wxchat / mtproxy
# 每个服务可选 Y 安装、N 跳过；安装时配置端口映射与挂载目录（可跳过用默认）

set -e

die() { echo "[ERROR] $*" >&2; exit 1; }
info() { echo "[INFO] $*" >&2; }

# 将路径转为绝对路径并确保目录存在（含父目录）；相对路径按根路径解析，如 home/volumes/lucky -> /home/volumes/lucky
ensure_absolute_dir() {
  local dir="$1"
  [ -z "$dir" ] && return 0
  [[ "$dir" != /* ]] && dir="/$dir"
  mkdir -p "$dir"
  echo "$dir"
}

# ---- 1. 前置检查 ----
check_root() {
  if [ "$(id -u)" -ne 0 ]; then
    die "请使用 root 运行此脚本，或使用: sudo $0"
  fi
}

# ---- 2. 安装 Docker ----
install_docker() {
  if command -v docker &>/dev/null; then
    info "Docker 已安装: $(docker --version)"
    return 0
  fi
  info "未检测到 Docker，开始安装..."
  if command -v curl &>/dev/null; then
    curl -fsSL https://get.docker.com | sh
  elif command -v wget &>/dev/null; then
    wget -qO- https://get.docker.com | sh
  else
    die "需要 curl 或 wget，请先安装其一"
  fi
  systemctl enable docker 2>/dev/null || true
  systemctl start docker 2>/dev/null || true
  info "Docker 安装完成: $(docker --version)"
}

# ---- 3. 交互：是否安装 ----
confirm_install() {
  local name="$1"
  echo -n "是否安装 ${name}? [Y/n] "
  read -r ans
  case "$ans" in
    [nN]|[nN][oO]) return 1 ;;
    *) return 0 ;;
  esac
}

# ---- 4. 部署 Portainer ----
install_portainer() {
  if docker ps -a --format '{{.Names}}' | grep -qx portainer; then
    info "容器 portainer 已存在，跳过"
    return 0
  fi
  local host_port=9000
  local mount_dir=""
  echo -n "Portainer 端口映射 [默认 9000，直接回车使用默认]: "
  read -r p
  if [ -n "$p" ]; then
    host_port="$p"
  fi
  echo -n "Portainer 数据挂载目录 [可选，直接回车跳过]: "
  read -r mount_dir
  local run_cmd="docker run -d \
  -p ${host_port}:9000 \
  --name portainer \
  --restart=always \
  -v /var/run/docker.sock:/var/run/docker.sock"
  if [ -n "$mount_dir" ]; then
    mount_dir="$(ensure_absolute_dir "$mount_dir")"
    info "使用目录: $mount_dir"
    run_cmd="${run_cmd} \
  -v ${mount_dir}:/data"
  fi
  run_cmd="${run_cmd} \
  portainer/portainer-ce:latest"
  info "执行: $run_cmd"
  eval "$run_cmd"
  info "Portainer 已启动，访问 http://<本机IP>:${host_port}"
}

# ---- 5. 部署 Lucky ----
install_lucky() {
  if docker ps -a --format '{{.Names}}' | grep -qx lucky; then
    info "容器 lucky 已存在，跳过"
    return 0
  fi
  local host_port=16601
  local mount_dir="/opt/lucky"
  local cert_dir=""
  echo -n "Lucky 端口映射 [默认 16601，直接回车使用默认]: "
  read -r p
  if [ -n "$p" ]; then
    host_port="$p"
  fi
  echo -n "Lucky 挂载目录 [默认 /opt/lucky，直接回车使用默认]: "
  read -r m
  if [ -n "$m" ]; then
    mount_dir="$m"
  fi
  echo -n "Lucky 证书目录 [可选，直接回车跳过]: "
  read -r cert_dir
  mount_dir="$(ensure_absolute_dir "$mount_dir")"
  info "使用目录: $mount_dir"
  if [ -n "$cert_dir" ]; then
    cert_dir="$(ensure_absolute_dir "$cert_dir")"
    info "使用目录: $cert_dir"
  fi
  local run_cmd="docker run -d \
  --name lucky \
  --restart=unless-stopped \
  -p ${host_port}:16601 \
  -v ${mount_dir}:/goodluck \
  -e TZ=Asia/Shanghai \
  gdy666/lucky:latest"
  if [ -n "$cert_dir" ]; then
    run_cmd="${run_cmd} \
  -v ${cert_dir}:/zs"
  fi
  info "执行: $run_cmd"
  eval "$run_cmd"
  info "Lucky 已启动，端口 ${host_port}"
}

# ---- 6. 部署 WxChat ----
install_wxchat() {
  if docker ps -a --format '{{.Names}}' | grep -qx wxchat; then
    info "容器 wxchat 已存在，跳过"
    return 0
  fi
  local host_port=38090
  echo -n "WxChat 端口映射 [默认 38090，直接回车使用默认]: "
  read -r p
  if [ -n "$p" ]; then
    host_port="$p"
  fi
  local run_cmd="docker run -d \
  --name wxchat \
  --restart=always \
  -p ${host_port}:80 \
  ddsderek/wxchat:latest"
  info "执行: $run_cmd"
  eval "$run_cmd"
  info "WxChat 已启动，访问 http://<本机IP>:${host_port}"
}

# ---- 7. 部署 MTProxy ----
install_mtproxy() {
  if docker ps -a --format '{{.Names}}' | grep -qx mtproxy; then
    info "容器 mtproxy 已存在，跳过"
    return 0
  fi
  local port_80=8080
  local port_443=8443
  local domain="cloudflare.com"
  local secret="548593a9c0688f4f7d9d57377897d964"

  echo -n "MTProxy 端口 80 映射 [默认 8080]: "
  read -r p
  [ -n "$p" ] && port_80="$p"
  echo -n "MTProxy 端口 443 映射 [默认 8443]: "
  read -r p
  [ -n "$p" ] && port_443="$p"
  echo -n "MTProxy domain [默认 cloudflare.com]: "
  read -r p
  [ -n "$p" ] && domain="$p"
  echo -n "MTProxy secret [默认 548593a9c0688f4f7d9d57377897d964]: "
  read -r p
  [ -n "$p" ] && secret="$p"

  local run_cmd="docker run -d \
  --name mtproxy \
  --restart=always \
  -e domain=\"${domain}\" \
  -e secret=\"${secret}\" \
  -e ip_white_list=\"OFF\" \
  -e provider=2 \
  -p ${port_80}:80 \
  -p ${port_443}:443 \
  ellermister/mtproxy"
  info "执行: $run_cmd"
  eval "$run_cmd"
  info "MTProxy 已启动，HTTP 端口 ${port_80}，HTTPS 端口 ${port_443}"
}

# ---- 8. 主流程 ----
main() {
  check_root
  install_docker

  info "-------- 1. Portainer (portainer/portainer-ce) --------"
  if confirm_install "Portainer"; then
    install_portainer
  else
    info "跳过 Portainer"
  fi

  info "-------- 2. Lucky (gdy666/lucky) --------"
  if confirm_install "Lucky"; then
    install_lucky
  else
    info "跳过 Lucky"
  fi

  info "-------- 3. WxChat (ddsderek/wxchat) --------"
  if confirm_install "WxChat"; then
    install_wxchat
  else
    info "跳过 WxChat"
  fi

  info "-------- 4. MTProxy (ellermister/mtproxy) --------"
  if confirm_install "MTProxy"; then
    install_mtproxy
  else
    info "跳过 MTProxy"
  fi

  info "全部完成。当前容器:"
  docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
}

main "$@"
