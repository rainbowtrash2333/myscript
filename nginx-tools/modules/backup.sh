#!/usr/bin/env bash
# =====================================================
# modules/backup.sh - 备份管理模块
# =====================================================
# 子命令: create, list, restore, cleanup, help
# 用法:   nginx-tools backup <subcommand> [args...]
# =====================================================

# ===== 帮助信息 =====
_backup_help() {
    cat <<EOF
nginx-tools backup - 备份管理

用法:
  nginx-tools backup <subcommand> [args...]

可用子命令:
  create [label]       创建完整 nginx 配置备份 (默认标签: manual)
  list                 列出所有备份文件
  restore <file>       从备份还原配置 (需确认)
  cleanup [days]       清理旧备份 (默认: 30 天前)
  help                 显示此帮助信息

示例:
  nginx-tools backup create
  nginx-tools backup create pre-upgrade
  nginx-tools backup list
  nginx-tools backup restore nginx-config-manual-20260529-120000.tar.gz
  nginx-tools backup cleanup 7
EOF
}

# ===== 创建备份 =====
_backup_create() {
    local _backup_label="${1:-manual}"
    local _backup_path

    print_banner "创建备份"

    _backup_path="$(backup_nginx_config "$_backup_label")"

    if [[ -n "$_backup_path" ]] && [[ -f "$_backup_path" ]]; then
        local _backup_size
        _backup_size="$(du -h "$_backup_path" 2>/dev/null | cut -f1)"
        log_ok "备份完成"
        log_info "路径: ${_backup_path}"
        log_info "大小: ${_backup_size}"
    fi
}

# ===== 列出备份 =====
_backup_list() {
    print_banner "备份列表"

    local _backup_dir
    _backup_dir="$(get_backup_dir)"

    if [[ -d "$_backup_dir" ]]; then
        local _backup_count
        _backup_count="$(find "$_backup_dir" -name "*.tar.gz" -type f 2>/dev/null | wc -l)"

        if [[ "$_backup_count" -eq 0 ]]; then
            log_info "当前没有备份文件"
            log_info "备份目录: ${_backup_dir}"
        else
            backup_list
        fi
    else
        log_info "备份目录不存在: ${_backup_dir}"
        log_info "尚未创建任何备份"
    fi
}

# ===== 还原备份 =====
_backup_restore() {
    local _backup_file="$1"

    if [[ -z "$_backup_file" ]]; then
        log_error "请指定要还原的备份文件"
        log_info "用法: nginx-tools backup restore <file>"
        log_info "运行 'nginx-tools backup list' 查看可用备份"
        return 1
    fi

    # 验证备份文件是否存在
    local _backup_dir
    _backup_dir="$(get_backup_dir)"

    if [[ ! -f "$_backup_file" ]] && [[ ! -f "${_backup_dir}/${_backup_file}" ]]; then
        log_error "备份文件不存在: ${_backup_file}"
        log_info "备份目录: ${_backup_dir}"
        log_info "运行 'nginx-tools backup list' 查看可用备份"
        return 1
    fi

    print_banner "还原备份"

    log_warn "还原操作将覆盖当前 nginx 配置！"
    log_warn "还原前会自动备份当前配置。"

    if ! confirm "确认从备份还原？" "n"; then
        log_info "已取消还原"
        return 0
    fi

    acquire_lock
    backup_restore "$_backup_file"
}

# ===== 清理旧备份 =====
_backup_cleanup() {
    local _backup_days="${1:-30}"

    # 校验天数是否为数字
    if [[ ! "$_backup_days" =~ ^[0-9]+$ ]]; then
        log_error "无效的天数: ${_backup_days}，请输入数字"
        return 1
    fi

    print_banner "清理旧备份"
    log_info "清理 ${_backup_days} 天前的备份..."

    backup_cleanup "$_backup_days"
}

# ===== 主入口 =====
_backup_main() {
    local _backup_subcmd="${1:-help}"
    shift 2>/dev/null || true

    case "$_backup_subcmd" in
        create)
            _backup_create "$@"
            ;;
        list)
            _backup_list "$@"
            ;;
        restore)
            _backup_restore "$@"
            ;;
        cleanup)
            _backup_cleanup "$@"
            ;;
        help|--help|-h)
            _backup_help
            ;;
        *)
            log_error "未知子命令: ${_backup_subcmd}"
            _backup_help
            return 1
            ;;
    esac
}
