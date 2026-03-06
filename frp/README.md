# frps 服务端一键安装 / 卸载

从 [fatedier/frp Releases](https://github.com/fatedier/frp/releases) 自动下载并安装 **frps**（frp 服务端），交互式配置后通过 systemd 开机自启。

## 环境要求

- **系统**：Linux（如 Debian/Ubuntu、CentOS/RHEL）
- **权限**：root 或 `sudo`
- **依赖**：`curl` 或 `wget`、`tar`（可选 `jq` 用于从 API 获取最新版本）

## 安装

```bash
sudo ./install-frps.sh
```

脚本会：

1. 检测是否已存在配置文件，询问是否覆盖
2. 根据架构（amd64/arm64/arm）从 GitHub 下载最新版 frps 并安装到 `/usr/local/bin/frps`
3. 按提示输入必填与可选参数，生成 `/etc/frp/frps.toml`
4. 注册并启用 systemd 服务 `frps`，并启动

### 安装时的参数

**必填**

| 参数 | 说明 |
|------|------|
| bindPort | 服务端监听端口，供 frpc 连接（如 7000） |
| vhostHTTPPort | HTTP 类型代理监听端口 |
| auth.method | 认证方式，默认 `token`，回车即用默认 |
| auth.token | 与客户端一致的 Token 字符串 |

**可选**

| 参数 | 说明 | 默认 |
|------|------|------|
| webServer.port | Dashboard 端口，不填则不启用 | - |
| webServer.addr | Dashboard 监听地址 | 0.0.0.0 |
| webServer.user | HTTP BasicAuth 用户名 | admin |
| webServer.password | HTTP BasicAuth 密码 | admin |

- 若已存在 `/etc/frp/frps.toml`，会询问是否覆盖；选「否」则只更新二进制与 systemd，不改写配置、不再次询问上述参数。
- 若已存在 `/usr/local/bin/frps`，会询问是否覆盖二进制。

## 卸载

```bash
sudo ./uninstall-frps.sh
```

将执行：

- 停止并禁用 systemd 服务 `frps`
- 删除 `/etc/systemd/system/frps.service`
- 删除 `/usr/local/bin/frps`
- 询问是否删除配置目录 `/etc/frp`（可选保留配置）

## 安装后的路径与常用命令

| 项目 | 路径/命令 |
|------|-----------|
| 配置文件 | `/etc/frp/frps.toml` |
| 可执行文件 | `/usr/local/bin/frps` |
| 服务名 | `frps` |

```bash
systemctl status frps    # 查看状态
systemctl restart frps   # 重启
systemctl stop frps      # 停止
journalctl -u frps -f    # 查看日志
```

修改配置后需重启生效：

```bash
sudo systemctl restart frps
```

## 版本说明

- 优先通过 GitHub API（需 `jq`）或 `releases/latest` 重定向获取最新版本号
- 网络不可达时使用脚本内嵌版本（如 v0.67.0）
- 支持架构：x86_64(amd64)、aarch64/arm64、armv7l/arm

## 文件列表

| 文件 | 说明 |
|------|------|
| `install-frps.sh` | 安装并配置 frps，配置 systemd 自启 |
| `uninstall-frps.sh` | 一键卸载 frps 与可选删除配置 |
| `README.md` | 本说明文档 |
