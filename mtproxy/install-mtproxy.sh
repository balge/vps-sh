#!/bin/bash
# MTProxy 一键安装脚本（非 Docker）
# 使用 ellermister/mtproxy 官方脚本：清空 /home/mtproxy，下载并执行 mtproxy.sh
# 安装完成后配置开机自启（/etc/rc.local）与计划任务守护（crontab），参考：
# https://github.com/ellermister/mtproxy

set -e

MTPROXY_DIR="/home/mtproxy"
MTPROXY_SCRIPT_URL="https://github.com/ellermister/mtproxy/raw/master/mtproxy.sh"
MTPROXY_START_CMD="cd ${MTPROXY_DIR} && bash mtproxy.sh start > /dev/null 2>&1 &"

die() { echo "[ERROR] $*" >&2; exit 1; }
info() { echo "[INFO] $*" >&2; }

# ---- 1. 前置检查 ----
check_root() {
  if [ "$(id -u)" -ne 0 ]; then
    die "请使用 root 运行此脚本，或使用: sudo $0"
  fi
}

check_curl() {
  command -v curl &>/dev/null || die "需要 curl，请先安装"
}

# ---- 2. 安装流程 ----
install_mtproxy() {
  info "清空并创建目录: ${MTPROXY_DIR}"
  rm -rf "${MTPROXY_DIR}" && mkdir -p "${MTPROXY_DIR}" && cd "${MTPROXY_DIR}"

  info "下载 mtproxy.sh ..."
  curl -fsSL -o mtproxy.sh "${MTPROXY_SCRIPT_URL}"

  info "执行 mtproxy.sh（后续为交互式配置）"
  bash mtproxy.sh
}

# ---- 3. 开机自启（参考官方文档） ----
# 写入 /etc/rc.local；并添加 crontab 每分钟守护（官方建议：pid>65535 时进程易异常，用计划任务守护）
setup_autostart() {
  if [ ! -f "${MTPROXY_DIR}/mtproxy.sh" ]; then
    info "未检测到 ${MTPROXY_DIR}/mtproxy.sh，跳过开机自启配置（请先完成 mtproxy.sh 交互安装）"
    return 0
  fi

  # 3.1 开机启动：/etc/rc.local
  local rclocal="/etc/rc.local"
  local marker="mtproxy.sh start"
  if [ -f "$rclocal" ]; then
    if grep -q "$marker" "$rclocal" 2>/dev/null; then
      info "已存在 MTProxy 开机启动项，跳过"
    else
      # 在 exit 0 前插入（若有）
      if grep -q 'exit 0' "$rclocal" 2>/dev/null; then
        sed -i "/exit 0/i ${MTPROXY_START_CMD}" "$rclocal"
      else
        echo "$MTPROXY_START_CMD" >> "$rclocal"
      fi
      chmod +x "$rclocal"
      info "已添加开机启动: ${rclocal}"
    fi
  else
    # 创建 rc.local（systemd 下需启用 rc-local.service）
    cat > "$rclocal" << EOF
#!/bin/bash
# rc.local - MTProxy 等开机自启
${MTPROXY_START_CMD}
exit 0
EOF
    chmod +x "$rclocal"
    info "已创建并添加 MTProxy: ${rclocal}"
    if command -v systemctl &>/dev/null && [ -f /etc/systemd/system/rc-local.service ] || [ -f /lib/systemd/system/rc-local.service ]; then
      systemctl enable rc-local.service 2>/dev/null || true
      info "已启用 rc-local.service"
    fi
  fi

  # 3.2 计划任务守护：每分钟检测并启动（官方推荐，应对 pid>65535 时的进程异常）
  local cron_line="* * * * * ${MTPROXY_START_CMD}"
  local current_cron
  current_cron="$(crontab -l 2>/dev/null)" || true
  if echo "$current_cron" | grep -q "mtproxy.sh start"; then
    info "crontab 中已存在 MTProxy 守护，跳过"
  else
    (echo "$current_cron"; echo "$cron_line") | crontab -
    info "已添加 crontab 守护（每分钟检测并启动 MTProxy）"
  fi
}

# ---- 4. 主流程 ----
main() {
  check_root
  check_curl
  install_mtproxy
  info "安装流程结束，正在配置开机自启与计划任务守护..."
  setup_autostart
  info "全部完成。后续可手动：bash mtproxy.sh start/stop/restart，或 reinstall 重新配置。"
}

main "$@"
