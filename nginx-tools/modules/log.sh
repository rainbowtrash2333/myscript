#!/usr/bin/env bash
# =====================================================
# modules/log.sh - 日志查看模块
# =====================================================
# 子命令: access, error, tail, help
# 用法:   nginx-tools log <subcommand> [args...]
# =====================================================

# -----------------------------
# 帮助信息
# -----------------------------
_log_help() {
    cat <<EOF
nginx-tools log - 日志查看

用法:
  nginx-tools log <subcommand> [args...]

可用子命令:
  access [lines]           查看访问日志 (默认最后 50 行)
  error [lines]            查看错误日志 (默认最后 50 行)
  tail <access|error>      实时跟踪日志 (Ctrl+C 退出)
  help                     显示此帮助信息

示例:
  nginx-tools log access
  nginx-tools log access 100
  nginx-tools log error 20
  nginx-tools log tail access
  nginx-tools log tail error
EOF
}

# -----------------------------
# _log_detect_access_log - 检测访问日志路径
# -----------------------------
_log_detect_access_log() {
    local _log_path=""

    # 从 nginx 完整配置中解析 access_log 路径 (跳过 off)
    if is_command nginx; then
        _log_path=$(nginx -T 2>/dev/null | sed -n 's/.*access_log\s\+\([^;\s]*\).*/\1/p' | grep -v '^off$' | head -1) || true
    fi

    # 回退到默认路径
    if [[ -z "$_log_path" ]]; then
        local _log_dir
        _log_dir="$(get_nginx_log_dir)"
        _log_path="${_log_dir}/access.log"
    fi

    echo "$_log_path"
}

# -----------------------------
# _log_detect_error_log - 检测错误日志路径
# -----------------------------
_log_detect_error_log() {
    local _log_path=""

    # 从 nginx 完整配置中解析 error_log 路径 (跳过 off / stderr / syslog 等)
    if is_command nginx; then
        _log_path=$(nginx -T 2>/dev/null | sed -n 's/.*error_log\s\+\([^;\s]*\).*/\1/p' | grep -vE '^(off|stderr|syslog|debug|info|notice|warn|error|crit|alert|emerg)$' | head -1) || true
    fi

    # 回退到默认路径
    if [[ -z "$_log_path" ]]; then
        local _log_dir
        _log_dir="$(get_nginx_log_dir)"
        _log_path="${_log_dir}/error.log"
    fi

    echo "$_log_path"
}

# -----------------------------
# _log_validate_lines - 验证行数参数
# -----------------------------
_log_validate_lines() {
    local _log_input="$1"
    local _log_lines="${_log_input:-50}"

    # 必须是纯数字
    if ! [[ "$_log_lines" =~ ^[0-9]+$ ]]; then
        die "行数必须为正整数: ${_log_input}"
    fi

    # 不能为 0
    if [[ "$_log_lines" -eq 0 ]]; then
        die "行数不能为 0"
    fi

    echo "$_log_lines"
}

# -----------------------------
# _log_access - 查看访问日志
# -----------------------------
_log_access() {
    local _log_lines
    _log_lines="$(_log_validate_lines "${1:-50}")"

    local _log_file
    _log_file="$(_log_detect_access_log)"

    if [[ ! -f "$_log_file" ]]; then
        die "访问日志文件不存在: ${_log_file}"
    fi

    if [[ ! -r "$_log_file" ]]; then
        die "无权限读取访问日志: ${_log_file}"
    fi

    local _log_size
    _log_size=$(wc -l < "$_log_file" 2>/dev/null) || _log_size=0

    if [[ "$_log_size" -eq 0 ]]; then
        log_info "访问日志为空: ${_log_file}"
        return 0
    fi

    print_banner "访问日志 (最后 ${_log_lines} 行)"
    echo "  文件: ${_log_file}"
    echo "  总行数: ${_log_size}"
    echo
    print_separator "-"
    tail -n "$_log_lines" "$_log_file"
    print_separator "-"
}

# -----------------------------
# _log_error - 查看错误日志
# -----------------------------
_log_error() {
    local _log_lines
    _log_lines="$(_log_validate_lines "${1:-50}")"

    local _log_file
    _log_file="$(_log_detect_error_log)"

    if [[ ! -f "$_log_file" ]]; then
        die "错误日志文件不存在: ${_log_file}"
    fi

    if [[ ! -r "$_log_file" ]]; then
        die "无权限读取错误日志: ${_log_file}"
    fi

    local _log_size
    _log_size=$(wc -l < "$_log_file" 2>/dev/null) || _log_size=0

    if [[ "$_log_size" -eq 0 ]]; then
        log_info "错误日志为空: ${_log_file}"
        return 0
    fi

    print_banner "错误日志 (最后 ${_log_lines} 行)"
    echo "  文件: ${_log_file}"
    echo "  总行数: ${_log_size}"
    echo
    print_separator "-"
    tail -n "$_log_lines" "$_log_file"
    print_separator "-"
}

# -----------------------------
# _log_tail - 实时跟踪日志
# -----------------------------
_log_tail() {
    local _log_type="${1:-}"
    require_arg "日志类型 (access|error)" "$_log_type"

    local _log_file=""

    case "$_log_type" in
        access)
            _log_file="$(_log_detect_access_log)"
            ;;
        error)
            _log_file="$(_log_detect_error_log)"
            ;;
        *)
            die "未知日志类型: ${_log_type}。可用: access, error"
            ;;
    esac

    if [[ ! -f "$_log_file" ]]; then
        die "日志文件不存在: ${_log_file}"
    fi

    if [[ ! -r "$_log_file" ]]; then
        die "无权限读取日志: ${_log_file}"
    fi

    acquire_lock

    log_step "正在跟踪日志: ${_log_file}"
    log_info "按 Ctrl+C 停止跟踪"
    echo

    # 设置 Ctrl+C 优雅退出
    trap 'echo; log_info "已停止跟踪"; exit 0' INT TERM

    tail -f "$_log_file"
}

# -----------------------------
# 主入口 (由 nginx-tools 调用)
# -----------------------------
_log_main() {
    local _log_subcmd="${1:-help}"
    shift 2>/dev/null || true

    case "$_log_subcmd" in
        access)
            _log_access "$@"
            ;;
        error)
            _log_error "$@"
            ;;
        tail)
            _log_tail "$@"
            ;;
        help|--help|-h)
            _log_help
            ;;
        *)
            log_error "未知子命令: ${_log_subcmd}"
            _log_help
            return 1
            ;;
    esac
}
