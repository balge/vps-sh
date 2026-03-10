#!/usr/bin/env python3 青龙/python环境，dockercli cmd都可以运行
"""
Sing-Box 节点更新脚本
从订阅链接获取节点并更新到 config.json，保持其他配置不变
"""

import json
import requests
import sys
import os
import re
from datetime import datetime

# 配置，自己映射路径
CONFIG_PATH = "/singbox/config.json"
BACKUP_PATH = "/singbox/config.json.backup"

# 订阅链接（支持 sing-box 格式和原生格式）
SUBSCRIPTION_URLS = [
]

# 固定的 outbound 配置（不会被替换），按照自己已有配置替换
FIXED_OUTBOUNDS = [
    {
        "tag": "select",
        "type": "selector",
        "default": "urltest",
        "outbounds": []
    },
    {
        "tag": "urltest",
        "type": "urltest",
        "outbounds": []
    },
    {
        "type": "direct",
        "tag": "direct_out"
    },
    {
        "type": "block",
        "tag": "block_out"
    },
    {
        "type": "dns",
        "tag": "dns_out"
    }
]

# 固定的代理节点（始终添加到末尾）
FIXED_PROXY_NODES = [
  
]


def parse_native_subscription(content):
    """解析原生订阅格式（base64编码的节点链接）"""
    import base64
    
    try:
        # 尝试 base64 解码
        decoded = base64.b64decode(content).decode('utf-8')
        lines = decoded.strip().split('\n')
        
        nodes = []
        for line in lines:
            line = line.strip()
            if not line:
                continue
            
            try:
                # 解析 vless:// 链接
                if line.startswith('vless://'):
                    node = parse_vless_url(line)
                    if node:
                        nodes.append(node)
                # 可以添加其他协议的解析
                # elif line.startswith('vmess://'):
                #     node = parse_vmess_url(line)
                # elif line.startswith('trojan://'):
                #     node = parse_trojan_url(line)
            except Exception as e:
                print(f"  ⚠ 跳过无法解析的节点: {line[:50]}... ({e})")
                continue
        
        return nodes
    except Exception as e:
        print(f"  ✗ base64 解码失败: {e}")
        return []


def parse_vless_url(url):
    """解析 vless:// URL 为 sing-box 格式"""
    from urllib.parse import urlparse, parse_qs, unquote
    
    # vless://uuid@server:port?params#tag
    if not url.startswith('vless://'):
        return None
    
    try:
        # 移除协议前缀
        url_without_protocol = url[8:]
        
        # 分离标签
        if '#' in url_without_protocol:
            url_part, tag = url_without_protocol.rsplit('#', 1)
            tag = unquote(tag)
        else:
            url_part = url_without_protocol
            tag = "vless_node"
        
        # 分离参数
        if '?' in url_part:
            auth_server, params_str = url_part.split('?', 1)
            params = parse_qs(params_str)
        else:
            auth_server = url_part
            params = {}
        
        # 解析 uuid@server:port
        if '@' not in auth_server:
            return None
        
        uuid, server_port = auth_server.split('@', 1)
        
        if ':' not in server_port:
            return None
        
        server, port = server_port.rsplit(':', 1)
        
        # 获取参数值的辅助函数
        def get_param(key, default=''):
            val = params.get(key, [default])
            return val[0] if val else default
        
        # 构建 sing-box 节点配置
        node = {
            "type": "vless",
            "tag": tag,
            "server": "68.64.180.12",
            "server_port": int(port),
            "uuid": uuid
        }
        
        security = get_param('security', 'none')
        network = get_param('type', 'tcp')
        flow = get_param('flow', '')
        
        # 处理 Reality
        if security == 'reality':
            sni = get_param('sni', server)
            fp = get_param('fp', 'chrome')
            pbk = get_param('pbk', '')
            sid = get_param('sid', '')
            spx = get_param('spx', '')  # spider x 参数
            
            node["flow"] = flow
            node["packet_encoding"] = "xudp"
            node["tls"] = {
                "enabled": True,
                "insecure": False,
                "server_name": sni,
                "utls": {
                    "enabled": True,
                    "fingerprint": fp
                },
                "reality": {
                    "enabled": True,
                    "public_key": pbk,
                    "short_id": sid
                }
            }
            
            # 如果有 spx 参数，添加到 reality 配置中
            # if spx:
            #    node["tls"]["reality"]["short_id"] = sid
            
        elif security == 'tls':
            sni = get_param('sni', server)
            alpn = get_param('alpn', '')
            fp = get_param('fp', '')
            allow_insecure = get_param('allowInsecure', '0')
            
            # TLS 可能需要 flow
            if flow:
                node["flow"] = flow
            else:
                node["flow"] = ""
            
            node["packet_encoding"] = "xudp"
            node["tls"] = {
                "enabled": True,
                "insecure": allow_insecure == '1',
                "server_name": sni
            }
            
            if alpn:
                node["tls"]["alpn"] = alpn.split(',')
            
            if fp:
                node["tls"]["utls"] = {
                    "enabled": True,
                    "fingerprint": fp
                }
        else:
            # 无加密时也需要设置 flow 为空字符串
            node["flow"] = ""
            node["packet_encoding"] = "xudp"
        
        # 处理传输层（只有非 TCP 才需要 transport）
        if network == 'ws':
            path = get_param('path', '/')
            host = get_param('host', server)
            
            node["transport"] = {
                "type": "ws",
                "path": path,
                "headers": {
                    "Host": [host]
                }
            }
            
            # WebSocket 的 early_data
            early_data = get_param('ed', '')
            if early_data:
                node["transport"]["max_early_data"] = int(early_data)
                node["transport"]["early_data_header_name"] = "Sec-WebSocket-Protocol"
                
        elif network == 'grpc':
            service_name = get_param('serviceName', '')
            node["transport"] = {
                "type": "grpc",
                "service_name": service_name
            }
            
        elif network == 'h2' or network == 'http':
            path = get_param('path', '/')
            host = get_param('host', server)
            
            node["transport"] = {
                "type": "http",
                "path": path,
                "host": [host]
            }
        # TCP 不需要 transport 配置
        
        return node
        
    except Exception as e:
        print(f"  ✗ 解析 vless URL 失败: {e}")
        import traceback
        traceback.print_exc()
        return None


def fetch_subscription(url):
    """从订阅链接获取 sing-box 配置"""
    try:
        print(f"正在获取订阅: {url[:60]}...")
        
        response = requests.get(url, timeout=60, verify=False)
        response.raise_for_status()
        
        # 先尝试解析为 JSON (sing-box 格式)
        try:
            config = response.json()
            print(f"  ✓ 检测到 sing-box 格式")
            return config
        except json.JSONDecodeError:
            # 如果不是 JSON，尝试解析为原生订阅格式
            print(f"  ℹ 尝试解析为原生订阅格式")
            nodes = parse_native_subscription(response.text)
            if nodes:
                print(f"  ✓ 成功解析原生格式，获取 {len(nodes)} 个节点")
                return {"outbounds": nodes}
            else:
                print(f"  ✗ 无法解析订阅内容")
                return None
            
    except requests.exceptions.Timeout:
        print(f"  ✗ 请求超时")
        return None
    except requests.exceptions.ConnectionError:
        print(f"  ✗ 无法连接到订阅服务器")
        return None
    except Exception as e:
        print(f"  ✗ 获取订阅失败: {e}")
        return None


def clean_node_name(name):
    """清理节点名称：去除emoji和特殊字符"""
    if not name:
        return name
    
    # 去除emoji表情（更精确的Unicode范围，避免误删中文）
    emoji_pattern = re.compile(
        "["
        "\U0001F1E0-\U0001F1FF"  # 国旗 (flags)
        "\U0001F300-\U0001F5FF"  # 符号和象形文字
        "\U0001F600-\U0001F64F"  # 表情符号
        "\U0001F680-\U0001F6FF"  # 交通和地图符号
        "\U0001F700-\U0001F77F"  # 炼金术符号
        "\U0001F780-\U0001F7FF"  # 几何形状扩展
        "\U0001F800-\U0001F8FF"  # 补充箭头-C
        "\U0001F900-\U0001F9FF"  # 补充符号和象形文字
        "\U0001FA00-\U0001FA6F"  # 象棋符号
        "\U0001FA70-\U0001FAFF"  # 符号和象形文字扩展-A
        "\U00002600-\U000026FF"  # 杂项符号
        "\U00002700-\U000027BF"  # 装饰符号
        "\U0000FE00-\U0000FE0F"  # 变体选择器
        "\U0001F900-\U0001F9FF"  # 补充符号和象形文字
        "\U0001FA70-\U0001FAFF"  # 扩展符号
        "]+", 
        flags=re.UNICODE
    )
    name = emoji_pattern.sub('', name)
    
    # 替换特殊字符为下划线
    # 包括：- ｜ | . 等
    special_chars = ['-', '｜', '|', '.', '/', '\\', ':', '*', '?', '"', '<', '>', '（', '）', '(', ')']
    for char in special_chars:
        name = name.replace(char, '_')
    
    # 去除连续的下划线
    name = re.sub(r'_+', '_', name)
    
    # 去除首尾的下划线
    name = name.strip('_')
    
    # 最后去除所有空格
    name = name.replace(' ', '')
    
    return name


def extract_proxy_nodes(config):
    """从订阅配置中提取代理节点"""
    if not config or "outbounds" not in config:
        return []
    
    nodes = []
    for outbound in config["outbounds"]:
        # 只提取代理节点，排除 direct、block、dns、selector、urltest 等
        if outbound.get("type") in ["vmess", "vless", "trojan", "shadowsocks", "hysteria", "hysteria2", "tuic", "wireguard"]:
            # 清理节点名称
            if "tag" in outbound:
                original_tag = outbound["tag"]
                cleaned_tag = clean_node_name(original_tag)
                if cleaned_tag != original_tag:
                    print(f"  节点名称优化: {original_tag} -> {cleaned_tag}")
                outbound["tag"] = cleaned_tag
            
            # 修复 server_name 为 null 的问题
            if "tls" in outbound and outbound["tls"].get("enabled"):
                if outbound["tls"].get("server_name") is None:
                    # 如果 server_name 为 null，使用 server 字段的值
                    if "server" in outbound:
                        outbound["tls"]["server_name"] = outbound["server"]
                        print(f"  修复节点 {outbound.get('tag', 'unknown')} 的 server_name: null -> {outbound['server']}")
            
            nodes.append(outbound)
    
    return nodes


def update_config(config_path, new_nodes):
    """更新配置文件，只替换节点部分"""
    try:
        # 读取现有配置
        print(f"读取配置文件: {config_path}")
        with open(config_path, 'r', encoding='utf-8') as f:
            config = json.load(f)
        
        # 备份原配置
        print(f"备份配置到: {BACKUP_PATH}")
        with open(BACKUP_PATH, 'w', encoding='utf-8') as f:
            json.dump(config, f, indent=2, ensure_ascii=False)
        
        # 合并订阅节点和固定节点
        all_proxy_nodes = new_nodes + FIXED_PROXY_NODES
        
        # 提取所有节点的 tag
        node_tags = [node["tag"] for node in all_proxy_nodes if "tag" in node]
        
        # 更新 outbounds
        if "outbounds" not in config:
            config["outbounds"] = []
        
        # 保留固定的 outbound，移除旧的代理节点
        fixed_outbounds = []
        for outbound in config["outbounds"]:
            outbound_type = outbound.get("type")
            outbound_tag = outbound.get("tag")
            
            # 保留固定类型的 outbound
            if outbound_type in ["selector", "urltest", "direct", "block", "dns"] or \
               outbound_tag in ["select", "urltest", "direct_out", "block_out", "dns_out"]:
                fixed_outbounds.append(outbound)
        
        # 更新 selector 和 urltest 的 outbounds 列表
        for outbound in fixed_outbounds:
            if outbound.get("tag") == "select":
                # select 需要包含 urltest 和所有节点
                outbound["outbounds"] = ["urltest"] + node_tags
            elif outbound.get("tag") == "urltest":
                # urltest 只包含节点
                outbound["outbounds"] = node_tags
        
        # 如果没有找到固定的 outbound，使用默认配置
        if not fixed_outbounds:
            print("未找到固定配置，使用默认配置")
            fixed_outbounds = FIXED_OUTBOUNDS.copy()
            for outbound in fixed_outbounds:
                if outbound.get("tag") == "select":
                    outbound["outbounds"] = ["urltest"] + node_tags
                elif outbound.get("tag") == "urltest":
                    outbound["outbounds"] = node_tags
        
        # 组合新的 outbounds：固定配置 + 所有代理节点（订阅节点 + 固定节点）
        config["outbounds"] = fixed_outbounds + all_proxy_nodes
        
        # 写入新配置
        print(f"写入新配置到: {config_path}")
        with open(config_path, 'w', encoding='utf-8') as f:
            json.dump(config, f, indent=2, ensure_ascii=False)
        
        # 在 singbox 目录下创建 .restart，供 compose 的 watcher 检测并重启容器
        singbox_dir = os.path.dirname(config_path)
        restart_flag = os.path.join(singbox_dir, ".restart")
        try:
            open(restart_flag, "w").close()
            print(f"已创建 {restart_flag}，等待 sing-box 重启")
        except OSError as e:
            print(f"⚠ 创建 .restart 标记失败: {e}")
        
        print(f"✓ 配置更新成功！共 {len(all_proxy_nodes)} 个节点（订阅: {len(new_nodes)}, 固定: {len(FIXED_PROXY_NODES)}）")
        return True
        
    except Exception as e:
        print(f"✗ 更新配置失败: {e}")
        return False


def main():
    print("=" * 60)
    print("Sing-Box 节点更新脚本")
    print(f"时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("=" * 60)
    
    # 检查配置文件是否存在
    if not os.path.exists(CONFIG_PATH):
        print(f"✗ 配置文件不存在: {CONFIG_PATH}")
        sys.exit(1)
    
    # 从所有订阅获取节点
    all_nodes = []
    successful_subscriptions = 0
    
    for i, url in enumerate(SUBSCRIPTION_URLS, 1):
        print(f"\n[{i}/{len(SUBSCRIPTION_URLS)}] 处理订阅...")
        sub_config = fetch_subscription(url)
        if sub_config:
            nodes = extract_proxy_nodes(sub_config)
            if nodes:
                print(f"  ✓ 获取到 {len(nodes)} 个节点")
                all_nodes.extend(nodes)
                successful_subscriptions += 1
            else:
                print(f"  ⚠ 订阅 {i} 未获取到有效节点")
        else:
            print(f"  ✗ 订阅 {i} 获取失败，跳过")
    
    if not all_nodes:
        print(f"\n✗ 未获取到任何节点（成功: {successful_subscriptions}/{len(SUBSCRIPTION_URLS)}），退出")
        sys.exit(1)
    
    print(f"\n总计获取 {len(all_nodes)} 个节点（成功订阅: {successful_subscriptions}/{len(SUBSCRIPTION_URLS)}）")
    
    # 去重（根据 tag）
    seen_tags = set()
    unique_nodes = []
    for node in all_nodes:
        tag = node.get("tag", "")
        if tag and tag not in seen_tags:
            seen_tags.add(tag)
            unique_nodes.append(node)
    
    if len(unique_nodes) < len(all_nodes):
        print(f"去重后剩余 {len(unique_nodes)} 个节点")
    
    # 更新配置
    print("\n开始更新配置...")
    if update_config(CONFIG_PATH, unique_nodes):
        print("\n" + "=" * 60)
        print("✓ 节点更新完成！")
        print("=" * 60)
        sys.exit(0)
    else:
        print("\n✗ 节点更新失败")
        sys.exit(1)


if __name__ == "__main__":
    main()
