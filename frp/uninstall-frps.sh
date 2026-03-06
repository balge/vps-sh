#!/bin/bash
# frps 一键卸载脚本
# 停止并禁用服务，删除二进制、systemd 单元，可选删除配置目录

set -e

INSTALL_BIN="/usr/local/bin/frps"
CONFIG_DIR="/etc/frp"
CONFIG_FILE="${CONFIG_DIR}/frps.toml"
SYSTEMD_UNIT="/etc/systemd/system/frps.service"

die() { echo "[ERROR] $*" >&2; exit 1; }
info() { echo "[INFO] $*"; }

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

uninstall() {
  check_root
  check_linux

  local removed=0

  # 停止并禁用 systemd 服务
  if systemctl is-active --quiet frps 2>/dev/null; then
    info "停止 frps 服务..."
    systemctl stop frps
    removed=1
  fi
  if systemctl is-enabled --quiet frps 2>/dev/null; then
    info "禁用 frps 服务..."
    systemctl disable frps
    removed=1
  fi

  # 删除 systemd 单元文件
  if [ -f "$SYSTEMD_UNIT" ]; then
    info "删除 $SYSTEMD_UNIT"
    rm -f "$SYSTEMD_UNIT"
    removed=1
  fi

  if [ "$removed" = "1" ]; then
    systemctl daemon-reload
    info "已执行 systemctl daemon-reload"
  fi

  # 删除二进制
  if [ -f "$INSTALL_BIN" ]; then
    info "删除 $INSTALL_BIN"
    rm -f "$INSTALL_BIN"
    removed=1
  fi

  # 可选：删除配置目录
  if [ -d "$CONFIG_DIR" ]; then
    echo -n "是否删除配置文件目录 $CONFIG_DIR? [y/N] "
    read -r ans
    case "$ans" in
      [yY]|[yY][eE][sS])
        rm -rf "$CONFIG_DIR"
        info "已删除 $CONFIG_DIR"
        ;;
      *)
        info "保留配置目录: $CONFIG_DIR"
        ;;
    esac
  fi

  if [ "$removed" = "0" ] && [ ! -d "$CONFIG_DIR" ]; then
    info "未发现已安装的 frps，无需卸载"
  else
    echo ""
    echo "========== 卸载完成 =========="
    echo "  frps 服务与二进制已移除"
    echo "  若未删除配置，配置文件仍在: $CONFIG_FILE"
    echo ""
  fi
}

uninstall "$@"
