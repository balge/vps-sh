# MTProxy 一键安装（非 Docker）

使用 [ellermister/mtproxy](https://github.com/ellermister/mtproxy) 官方脚本，在 `/home/mtproxy` 下安装并运行 MTProxy（非 Docker 方式）。

## 环境要求

- **系统**：Linux
- **权限**：root 或 `sudo`
- **依赖**：`curl`

## 安装

```bash
sudo ./install-mtproxy.sh
```

脚本会：

1. 清空并创建目录 `/home/mtproxy`，进入该目录
2. 使用 `curl` 下载 `mtproxy.sh`（来自 GitHub 仓库）
3. 执行 `bash mtproxy.sh`，后续为官方脚本的交互式配置
4. **安装完成后** 自动配置：
   - **开机自启**：向 `/etc/rc.local` 写入 `cd /home/mtproxy && bash mtproxy.sh start ...`（若不存在会创建并启用 `rc-local.service`）
   - **计划任务守护**：为 root 添加 crontab `* * * * * ... mtproxy.sh start ...`（每分钟检测并启动，[官方建议](https://github.com/ellermister/mtproxy)用于应对 pid>65535 时进程异常）

## 等价命令（手动执行）

```bash
rm -rf /home/mtproxy && mkdir /home/mtproxy && cd /home/mtproxy
curl -fsSL -o mtproxy.sh https://github.com/ellermister/mtproxy/raw/master/mtproxy.sh
bash mtproxy.sh
```

## 与 Docker 方式区别

- 本脚本：直接装机，使用官方 shell 脚本，适合不想用 Docker 的 VPS；安装后自动配置 **开机自启**（`/etc/rc.local`）与 **crontab 守护**（每分钟检测并启动）。
- Docker 方式：见项目根目录 `docker/install-docker.sh` 中的 MTProxy 步骤，使用镜像 `ellermister/mtproxy`。

## 文件列表

| 文件 | 说明 |
|------|------|
| `install-mtproxy.sh` | 一键安装并进入官方 mtproxy.sh 交互 |
| `README.md` | 本说明文档 |
