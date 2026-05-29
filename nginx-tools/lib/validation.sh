#!/usr/bin/env bash
# =====================================================
# lib/validation.sh - 输入验证函数
# =====================================================

# -----------------------------
# 域名验证
# -----------------------------
is_valid_domain() {
    local domain="$1"
    # RFC 1123: 允许字母数字和连字符，不能以连字符开头或结尾
    # 支持通配符域名 *.example.com
    local pattern='^(\*\.)?([a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$'
    [[ "$domain" =~ $pattern ]]
}

validate_domain() {
    local domain="$1"
    local label="${2:-域名}"

    if [[ -z "$domain" ]]; then
        die "${label}不能为空"
    fi

    if ! is_valid_domain "$domain"; then
        die "无效的${label}: ${domain}"
    fi
}

# -----------------------------
# IP 地址验证
# -----------------------------
is_valid_ipv4() {
    local ip="$1"
    local pattern='^([0-9]{1,3}\.){3}[0-9]{1,3}$'

    if [[ ! "$ip" =~ $pattern ]]; then
        return 1
    fi

    # 验证每个八位组范围
    local IFS='.'
    for oct in $ip; do
        if [[ "$oct" -gt 255 ]] || [[ "$oct" -lt 0 ]]; then
            return 1
        fi
    done
    return 0
}

validate_ip() {
    local ip="$1"
    local label="${2:-IP 地址}"

    if [[ -z "$ip" ]]; then
        die "${label}不能为空"
    fi

    if ! is_valid_ipv4 "$ip"; then
        die "无效的${label}: ${ip}"
    fi
}

# -----------------------------
# 端口验证
# -----------------------------
is_valid_port() {
    local port="$1"
    [[ "$port" =~ ^[0-9]+$ ]] && [[ "$port" -ge 1 ]] && [[ "$port" -le 65535 ]]
}

validate_port() {
    local port="$1"
    local label="${2:-端口}"

    if [[ -z "$port" ]]; then
        die "${label}不能为空"
    fi

    if ! is_valid_port "$port"; then
        die "无效的${label}: ${port} (有效范围: 1-65535)"
    fi
}

# -----------------------------
# 站点名称验证 (用于 sites-available 中的文件名)
# -----------------------------
is_valid_site_name() {
    local name="$1"
    # 只允许字母数字、连字符、下划线、点
    [[ "$name" =~ ^[a-zA-Z0-9._-]+$ ]]
}

validate_site_name() {
    local name="$1"

    if [[ -z "$name" ]]; then
        die "站点名称不能为空"
    fi

    if ! is_valid_site_name "$name"; then
        die "无效的站点名称: ${name} (只允许字母数字、连字符、下划线、点)"
    fi
}

# -----------------------------
# Upstream 名称验证
# -----------------------------
is_valid_upstream_name() {
    local name="$1"
    [[ "$name" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]
}

validate_upstream_name() {
    local name="$1"

    if [[ -z "$name" ]]; then
        die "upstream 名称不能为空"
    fi

    if ! is_valid_upstream_name "$name"; then
        die "无效的 upstream 名称: ${name} (只能字母数字和下划线，且不能以数字开头)"
    fi
}

# -----------------------------
# 后端地址验证 (IP:PORT 或 HOST:PORT)
# -----------------------------
is_valid_backend() {
    local backend="$1"
    # 格式: host:port 或 ip:port
    [[ "$backend" =~ ^[a-zA-Z0-9._-]+:[0-9]{1,5}$ ]] || [[ "$backend" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]{1,5}$ ]]
}

validate_backend() {
    local backend="$1"
    if [[ -z "$backend" ]]; then
        die "后端地址不能为空"
    fi
    if ! is_valid_backend "$backend"; then
        die "无效的后端地址: ${backend} (格式: IP:PORT 或 HOST:PORT)"
    fi
}

# -----------------------------
# HTTP/HTTPS URL 验证
# -----------------------------
is_valid_url() {
    local url="$1"
    [[ "$url" =~ ^https?://[a-zA-Z0-9._-]+(:[0-9]{1,5})?(/.*)?$ ]]
}

validate_url() {
    local url="$1"
    if [[ -z "$url" ]]; then
        die "URL 不能为空"
    fi
    if ! is_valid_url "$url"; then
        die "无效的 URL: ${url}"
    fi
}

# -----------------------------
# 文件/目录存在性验证
# -----------------------------
validate_file() {
    local file="$1"
    local label="${2:-文件}"
    if [[ ! -f "$file" ]]; then
        die "${label}不存在: ${file}"
    fi
}

validate_dir() {
    local dir="$1"
    local label="${2:-目录}"
    if [[ ! -d "$dir" ]]; then
        die "${label}不存在: ${dir}"
    fi
}

# -----------------------------
# 协议验证 (TCP/UDP)
# -----------------------------
is_valid_protocol() {
    local proto="$1"
    [[ "$proto" == "tcp" || "$proto" == "udp" ]]
}

validate_protocol() {
    local proto="$1"
    if [[ -z "$proto" ]]; then
        die "协议不能为空"
    fi
    if ! is_valid_protocol "$proto"; then
        die "无效的协议: ${proto} (只支持 tcp 或 udp)"
    fi
}
