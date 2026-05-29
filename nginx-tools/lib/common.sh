#!/usr/bin/env bash
# =====================================================
# lib/common.sh - nginx-tools 公共函数库
# =====================================================
# 本文件不设置 set -e，由入口脚本统一控制
# 所有函数使用 local 变量，避免命名空间污染

# -----------------------------
# 颜色定义
# -----------------------------
if [[ -t 1 ]]; then
    COLOR_RESET='\033[0m'
    COLOR_RED='\033[31m'
    COLOR_GREEN='\033[32m'
    COLOR_YELLOW='\033[33m'
    COLOR_BLUE='\033[34m'
    COLOR_CYAN='\033[36m'
    COLOR_BOLD='\033[1m'
else
    COLOR_RESET=''
    COLOR_RED=''
    COLOR_GREEN=''
    COLOR_YELLOW=''
    COLOR_BLUE=''
    COLOR_CYAN=''
    COLOR_BOLD=''
fi

# -----------------------------
# 日志函数
# -----------------------------
log_info() {
    echo -e "${COLOR_GREEN}[INFO]${COLOR_RESET} $*"
}

log_warn() {
    echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} $*" >&2
}

log_error() {
    echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $*" >&2
}

log_step() {
    echo -e "${COLOR_CYAN}==>${COLOR_RESET} $*"
}

log_ok() {
    echo -e "${COLOR_GREEN}[OK]${COLOR_RESET} $*"
}

die() {
    log_error "$@"
    exit 1
}

# -----------------------------
# 提权检测
# -----------------------------
require_root() {
    if [[ "$(id -u)" == "0" ]]; then
        return 0
    fi
    if command -v sudo &>/dev/null && sudo -v &>/dev/null 2>&1; then
        exec sudo bash "$0" "$@"
    fi
    die "需要 root 或 sudo 权限运行"
    echo "请执行: sudo $(basename "$0")" >&2
    exit 1
}

# -----------------------------
# Dry-Run 模式
# -----------------------------
DRY_RUN="${NGINX_TOOLS_DRY_RUN:-0}"

run_cmd() {
    if [[ "$DRY_RUN" == "1" ]]; then
        log_info "[DRY-RUN] $*"
        return 0
    fi
    "$@"
}

is_dry_run() {
    [[ "$DRY_RUN" == "1" ]]
}

# -----------------------------
# 文件锁
# -----------------------------
_LOCK_FD=""
_LOCK_FILE="/var/run/nginx-tools.lock"

acquire_lock() {
    if [[ "$DRY_RUN" == "1" ]]; then
        return 0
    fi
    local lock_dir
    lock_dir="$(dirname "$_LOCK_FILE")"
    [[ -d "$lock_dir" ]] || mkdir -p "$lock_dir" 2>/dev/null || true

    exec 200>"$_LOCK_FILE"
    if ! flock -n 200; then
        die "另一个 nginx-tools 实例正在运行，请稍后重试"
    fi
    _LOCK_FD=200
}

release_lock() {
    if [[ -n "$_LOCK_FD" ]] && [[ "$DRY_RUN" != "1" ]]; then
        flock -u "$_LOCK_FD" 2>/dev/null || true
    fi
}

# -----------------------------
# Cleanup 陷阱
# -----------------------------
_CLEANUP_FUNCTIONS=()

register_cleanup() {
    _CLEANUP_FUNCTIONS+=("$1")
}

_run_cleanup() {
    local fn
    for fn in "${_CLEANUP_FUNCTIONS[@]}"; do
        "$fn" 2>/dev/null || true
    done
    release_lock
}

# -----------------------------
# 确认提示
# -----------------------------
confirm() {
    local prompt="${1:-确认操作？}"
    local default="${2:-n}"
    local yn

    if [[ "$NGINX_TOOLS_YES" == "1" ]]; then
        return 0
    fi

    if [[ "$default" == "y" ]]; then
        read -r -p "${prompt} [Y/n] " yn
        [[ "$yn" != "n" && "$yn" != "N" ]]
    else
        read -r -p "${prompt} [y/N] " yn
        [[ "$yn" == "y" || "$yn" == "Y" ]]
    fi
}

# -----------------------------
# 工具函数
# -----------------------------
is_command() {
    command -v "$1" &>/dev/null
}

# 生成时间戳
timestamp() {
    date +"%Y%m%d-%H%M%S"
}

# 打印分割线
print_separator() {
    local char="${1:-=}"
    local width="${2:-50}"
    printf '%*s\n' "$width" '' | tr ' ' "$char"
}

print_banner() {
    local title="$1"
    echo
    print_separator "="
    echo "  $title"
    print_separator "="
    echo
}

# -----------------------------
# 配置文件元数据读写
# -----------------------------
read_meta() {
    local file="$1"
    local key="$2"
    grep -oP "# nginx-tools:${key}=\K.*" "$file" 2>/dev/null || true
}

write_meta() {
    local file="$1"
    local key="$2"
    local value="$3"
    if grep -q "# nginx-tools:${key}=" "$file" 2>/dev/null; then
        sed -i "s|# nginx-tools:${key}=.*|# nginx-tools:${key}=${value}|" "$file"
    else
        sed -i "1i# nginx-tools:${key}=${value}" "$file"
    fi
}

# -----------------------------
# 字符串处理
# -----------------------------
trim() {
    local var="$*"
    var="${var#"${var%%[![:space:]]*}"}"
    var="${var%"${var##*[![:space:]]}"}"
    printf '%s' "$var"
}

# 检查变量是否为空
require_arg() {
    local name="$1"
    local value="$2"
    if [[ -z "$value" ]]; then
        die "缺少必需参数: ${name}"
    fi
}
