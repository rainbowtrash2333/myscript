#!/usr/bin/env bash
# =====================================================
# lib/backup-lib.sh - 备份与还原函数
# =====================================================

_BACKUP_DIR="/var/backups/nginx-tools"
_BACKUP_RETENTION_DAYS="${NGINX_TOOLS_BACKUP_RETENTION:-30}"

get_backup_dir() {
    echo "$_BACKUP_DIR"
}

# -----------------------------
# 备份 nginx 配置
# -----------------------------
backup_nginx_config() {
    local label="${1:-manual}"
    local ts backup_name backup_path

    ts=$(timestamp)
    backup_name="nginx-config-${label}-${ts}.tar.gz"
    backup_path="${_BACKUP_DIR}/${backup_name}"

    if is_dry_run; then
        log_info "[DRY-RUN] 将创建备份: ${backup_path}"
        echo "$backup_path"
        return 0
    fi

    ensure_dir "$_BACKUP_DIR"

    log_step "备份 nginx 配置..."

    local conf_dir
    conf_dir="$(get_nginx_conf_dir)"

    # 使用 run_cmd 包装，支持 dry-run
    tar -czf "$backup_path" -C / \
        "${conf_dir#/}/nginx.conf" \
        "${conf_dir#/}/sites-available" \
        "${conf_dir#/}/sites-enabled" \
        "${conf_dir#/}/conf.d" \
        "${conf_dir#/}/ssl" \
        "${conf_dir#/}/stream.d" \
        2>/dev/null || {
        log_error "备份创建失败"
        return 1
    }

    log_ok "备份已创建: ${backup_path}"
    echo "$backup_path"
}

# -----------------------------
# 备份单个站点配置（修改前自动调用）
# -----------------------------
backup_site_config() {
    local domain="$1"

    if is_dry_run; then
        log_info "[DRY-RUN] 将备份站点配置: ${domain}"
        return 0
    fi

    local ts backup_name backup_path
    local sites_available sites_enabled

    ts=$(timestamp)
    backup_name="site-${domain}-${ts}.tar.gz"
    backup_path="${_BACKUP_DIR}/${backup_name}"

    ensure_dir "$_BACKUP_DIR"
    sites_available="$(get_sites_available)"
    sites_enabled="$(get_sites_enabled)"

    local files_to_backup=()
    [[ -f "${sites_available}/${domain}" ]] && files_to_backup+=("${sites_available#/}/${domain}")
    [[ -L "${sites_enabled}/${domain}" ]] && files_to_backup+=("${sites_enabled#/}/${domain}")

    if [[ ${#files_to_backup[@]} -eq 0 ]]; then
        log_warn "没有找到站点 ${domain} 的配置文件"
        return 0
    fi

    tar -czf "$backup_path" -C / "${files_to_backup[@]}" 2>/dev/null || {
        log_error "站点配置备份失败"
        return 1
    }

    log_info "站点配置已备份: ${backup_path}"
    echo "$backup_path"
}

# -----------------------------
# 列出备份
# -----------------------------
backup_list() {
    ensure_dir "$_BACKUP_DIR"

    echo
    echo "备份目录: ${_BACKUP_DIR}"
    echo
    printf "%-50s %10s %s\n" "备份文件" "大小" "创建时间"
    print_separator "-" 75

    local file size mtime
    for file in "$_BACKUP_DIR"/*.tar.gz; do
        [[ -f "$file" ]] || continue
        size=$(du -h "$file" | cut -f1)
        mtime=$(stat -c '%y' "$file" 2>/dev/null | cut -d. -f1 || date -r "$file" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "unknown")
        printf "%-50s %10s %s\n" "$(basename "$file")" "$size" "$mtime"
    done
    echo
}

# -----------------------------
# 还原配置
# -----------------------------
backup_restore() {
    local backup_file="$1"

    if [[ -z "$backup_file" ]]; then
        die "请指定要还原的备份文件"
    fi

    # 支持只提供文件名
    if [[ ! -f "$backup_file" ]] && [[ -f "${_BACKUP_DIR}/${backup_file}" ]]; then
        backup_file="${_BACKUP_DIR}/${backup_file}"
    fi

    validate_file "$backup_file" "备份文件"

    if is_dry_run; then
        log_info "[DRY-RUN] 将还原备份: ${backup_file}"
        return 0
    fi

    # 先备份当前配置
    log_step "还原前先备份当前配置..."
    backup_nginx_config "pre-restore"

    log_step "还原配置: ${backup_file}..."

    local conf_dir
    conf_dir="$(get_nginx_conf_dir)"

    tar -xzf "$backup_file" -C / 2>/dev/null || {
        log_error "备份还原失败"
        return 1
    }

    log_ok "配置已还原"

    # 验证配置
    log_step "验证 nginx 配置..."
    if nginx_test; then
        log_ok "配置验证通过，可以执行 reload 使配置生效"
    else
        log_error "还原后的配置存在问题！请手动检查或使用其他备份"
        return 1
    fi
}

# -----------------------------
# 清理旧备份
# -----------------------------
backup_cleanup() {
    local retention="${1:-$_BACKUP_RETENTION_DAYS}"

    # 校验 retention 是合法正整数，防止非法值传入 find -mtime
    if ! [[ "$retention" =~ ^[0-9]+$ ]] || [[ "$retention" -lt 1 ]]; then
        log_error "无效的保留天数: ${retention}（须为正整数）"
        return 1
    fi

    if is_dry_run; then
        log_info "[DRY-RUN] 将清理 ${retention} 天前的备份"
        return 0
    fi

    # 目录不存在说明从未创建过备份，直接返回
    if [[ ! -d "$_BACKUP_DIR" ]]; then
        log_info "备份目录不存在，无需清理: ${_BACKUP_DIR}"
        return 0
    fi

    local count
    # find 加 || true 防止空目录时的非零退出码经 pipefail 中断脚本
    count=$(find "$_BACKUP_DIR" -name "*.tar.gz" -type f -mtime "+${retention}" 2>/dev/null | wc -l) || true

    if [[ "$count" -eq 0 ]]; then
        log_info "没有需要清理的旧备份"
        return 0
    fi

    log_step "清理 ${retention} 天前的备份 (共 ${count} 个)..."
    find "$_BACKUP_DIR" -name "*.tar.gz" -type f -mtime "+${retention}" -delete 2>/dev/null || true
    log_ok "已清理 ${count} 个旧备份"
}
