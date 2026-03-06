# Docker 自动安装与常用镜像部署

## 脚本说明

`install-docker.sh` 会：

1. **自动安装 Docker**  
   若未检测到 Docker，使用官方 [get.docker.com](https://get.docker.com) 脚本安装并启用、启动服务。

2. **按顺序交互式部署四个镜像**  
   - **Portainer** `portainer/portainer-ce:latest`  
   - **Lucky** `gdy666/lucky:latest`  
   - **WxChat** `ddsderek/wxchat:latest`  
   - **MTProxy** `ellermister/mtproxy`  

   每个服务会询问：**Y 安装 / N 跳过**。  
   选择安装时再询问：  
   - **端口映射**：直接回车则使用默认端口。  
   - **挂载目录**：可选，直接回车则按说明处理（Portainer 不加 `/data` 挂载，Lucky 使用默认目录）。

3. **封装为 `docker run` 命令**  
   根据你的输入生成并执行对应的 `docker run`，并在控制台打印执行的命令。

## 使用方法

```bash
# 需 root 或 sudo
sudo bash install-docker.sh
```

## 默认端口与挂载

| 服务      | 默认端口 | 挂载说明 |
|-----------|----------|----------|
| Portainer | 9000     | 可选，不设则不挂载 `/data` |
| Lucky     | 16601    | 可选，默认 `/opt/lucky` → `/goodluck`；可选证书目录 → `/zs` |
| WxChat    | 80       | 无挂载 |
| MTProxy   | 8080, 8443 | 无挂载；可配置 domain、secret |

## 示例

- 安装 Portainer：选 Y → 端口回车(9000) → 挂载回车(不挂载) 或输入如 `/data/portainer`。  
- 安装 Lucky：选 Y → 端口回车(16601) → 挂载回车(`/opt/lucky`) 或自定义目录。  
- 安装 WxChat：选 Y → 端口回车(80) 或输入如 8080。  
- 安装 MTProxy：选 Y → 按提示输入 80/443 端口及 domain、secret（直接回车即使用默认）。

脚本会输出实际执行的 `docker run` 命令，便于核对或复现。
