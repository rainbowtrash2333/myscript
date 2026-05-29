#!/usr/bin/env bash
# =====================================================
# modules/upstream.sh - upstream 负载均衡池管理模块
# =====================================================
# 子命令: create, add, remove, list, help
# 用法:   nginx-tools upstream <subcommand> [args...]
# =====================================================

# -----------------------------
# 常量
# -----------------------------
_UPSTREAM_FILE="/etc/nginx/conf.d/upstream_proxy.conf"

# -----------------------------
# 帮助信息
# -----------------------------
_upstream_help() {
    cat <<EOF
nginx-tools upstream - 负载均衡池管理 (upstream 块)

用法:
  nginx-tools upstream <subcommand> [args...]

可用子命令:
  create <name>                    创建空的 upstream 池
  add <name> <backend>             向 upstream 池添加后端 (格式: IP:PORT)
  remove <name> <backend>          从 upstream 池移除后端 (格式: IP:PORT)
  list                             列出所有 upstream 池及其后端
  help                             显示此帮助信息

示例:
  nginx-tools upstream create myapp
  nginx-tools upstream add myapp 127.0.0.1:3000
  nginx-tools upstream add myapp 127.0.0.1:3001
  nginx-tools upstream remove myapp 127.0.0.1:3000
  nginx-tools upstream list

upstream 配置文件: ${_UPSTREAM_FILE}
EOF
}

# -----------------------------
# _upstream_ensure_file - 确保 upstream 文件存在且被 nginx.conf 包含
# -----------------------------
_upstream_ensure_file() {
    local _upstream_conf_dir
    _upstream_conf_dir="$(dirname "$_UPSTREAM_FILE")"

    # 确保 conf.d 目录存在
    ensure_dir "$_upstream_conf_dir"

    # 确保 upstream 文件存在
    if [[ ! -f "$_UPSTREAM_FILE" ]]; then
        if is_dry_run; then
            log_info "[DRY-RUN] 将创建 upstream 配置文件: ${_UPSTREAM_FILE}"
        else
            : > "$_UPSTREAM_FILE" || die "无法创建 upstream 配置文件: ${_UPSTREAM_FILE}"
            log_info "已创建 upstream 配置文件: ${_UPSTREAM_FILE}"
        fi
    fi

    # 检查 nginx.conf 是否已包含 conf.d/*.conf
    local _upstream_conf_dir_path
    _upstream_conf_dir_path="$(get_nginx_conf_dir)"
    if ! grep -qE '^\s*include\s+.*/conf\.d/\*\.conf\s*;' "${_upstream_conf_dir_path}/nginx.conf" 2>/dev/null; then
        log_warn "nginx.conf 未包含 conf.d/*.conf，请手动添加:"
        echo "  include ${_upstream_conf_dir}/*.conf;"
    fi
}

# -----------------------------
# _upstream_exists - 检查 upstream 块是否存在
# -----------------------------
_upstream_exists() {
    local _upstream_name="$1"
    if [[ ! -f "$_UPSTREAM_FILE" ]]; then
        return 1
    fi
    grep -qE "^upstream\s+${_upstream_name}\s*\{" "$_UPSTREAM_FILE" 2>/dev/null
}

# -----------------------------
# _upstream_create - 创建空 upstream 块
# -----------------------------
_upstream_create() {
    local _upstream_name="$1"
    require_arg "upstream 名称" "$_upstream_name"
    validate_upstream_name "$_upstream_name"

    # 幂等: 已存在则跳过
    if _upstream_exists "$_upstream_name"; then
        log_info "upstream ${_upstream_name} 已存在，无需操作"
        return 0
    fi

    acquire_lock

    # 确保文件存在
    _upstream_ensure_file

    # 备份
    backup_nginx_config "pre-upstream-create-${_upstream_name}" > /dev/null

    # 预检
    log_step "预检: 验证当前 nginx 配置..."
    if ! nginx_test; then
        die "当前 nginx 配置存在问题，无法创建 upstream。请先修复配置"
    fi

    log_step "创建 upstream: ${_upstream_name}..."

    if is_dry_run; then
        log_info "[DRY-RUN] 将创建 upstream 块: ${_upstream_name}"
        return 0
    fi

    # 追加空 upstream 块到文件末尾
    {
        echo ""
        echo "upstream ${_upstream_name} {"
        echo "}"
    } >> "$_UPSTREAM_FILE" || die "写入 upstream 配置失败"

    # 后检
    log_step "后检: 验证 nginx 配置..."
    if ! nginx_test; then
        log_error "创建 upstream 后配置测试失败，正在回滚..."
        # 移除刚追加的块
        sed -i "/^upstream\s\+${_upstream_name}\s\+{/,/^}/d" "$_UPSTREAM_FILE" 2>/dev/null
        # 清理多余空行
        sed -i '/^$/N;/^\n$/d' "$_UPSTREAM_FILE" 2>/dev/null
        die "nginx 配置验证失败，已回滚。请检查 upstream 名称: ${_upstream_name}"
    fi

    log_ok "upstream ${_upstream_name} 已创建"
}

# -----------------------------
# _upstream_add - 向 upstream 池添加后端
# -----------------------------
_upstream_add() {
    local _upstream_name="$1"
    local _upstream_backend="$2"
    require_arg "upstream 名称" "$_upstream_name"
    require_arg "后端地址" "$_upstream_backend"
    validate_upstream_name "$_upstream_name"
    validate_backend "$_upstream_backend"

    # 检查 upstream 是否存在
    if ! _upstream_exists "$_upstream_name"; then
        die "upstream ${_upstream_name} 不存在，请先创建: nginx-tools upstream create ${_upstream_name}"
    fi

    # 检查后端是否已存在 (防重复)
    if grep -qE "^\s*server\s+${_upstream_backend}\s*;" "$_UPSTREAM_FILE" 2>/dev/null; then
        # 进一步检查是否在该 upstream 块内
        local _upstream_in_block=0
        local _upstream_line
        while IFS= read -r _upstream_line; do
            if [[ "$_upstream_line" =~ ^upstream[[:space:]]+${_upstream_name}[[:space:]]*\{ ]]; then
                _upstream_in_block=1
            elif [[ "$_upstream_line" =~ ^\} ]] && [[ "$_upstream_in_block" -eq 1 ]]; then
                _upstream_in_block=0
            elif [[ "$_upstream_in_block" -eq 1 ]] && \
                 echo "$_upstream_line" | grep -qE "^\s*server\s+${_upstream_backend}\s*;"; then
                log_info "后端 ${_upstream_backend} 已存在于 upstream ${_upstream_name}，无需操作"
                return 0
            fi
        done < "$_UPSTREAM_FILE"
    fi

    acquire_lock

    # 备份
    backup_nginx_config "pre-upstream-add-${_upstream_name}" > /dev/null

    # 预检
    log_step "预检: 验证当前 nginx 配置..."
    if ! nginx_test; then
        die "当前 nginx 配置存在问题，无法添加后端。请先修复配置"
    fi

    log_step "向 upstream ${_upstream_name} 添加后端: ${_upstream_backend}..."

    if is_dry_run; then
        log_info "[DRY-RUN] 将添加 server ${_upstream_backend}; 到 upstream ${_upstream_name}"
        return 0
    fi

    # 使用 sed 在 upstream 块的 } 前插入 server 行
    # 匹配: upstream NAME { ... } 的闭合 } ，在其前插入
    sed -i "/^upstream\s\+${_upstream_name}\s\+{/,/^}/ {
        /^}/ i\    server ${_upstream_backend};
    }" "$_UPSTREAM_FILE" || die "添加后端失败"

    # 后检
    log_step "后检: 验证 nginx 配置..."
    if ! nginx_test; then
        log_error "添加后端后配置测试失败，正在回滚..."
        sed -i "/^upstream\s\+${_upstream_name}\s\+{/,/^}/ {
            /server\s\+${_upstream_backend}\s*;/d
        }" "$_UPSTREAM_FILE" 2>/dev/null
        die "nginx 配置验证失败，已回滚。请检查后端地址: ${_upstream_backend}"
    fi

    log_ok "后端 ${_upstream_backend} 已添加到 upstream ${_upstream_name}"
}

# -----------------------------
# _upstream_remove - 从 upstream 池移除后端
# -----------------------------
_upstream_remove() {
    local _upstream_name="$1"
    local _upstream_backend="$2"
    require_arg "upstream 名称" "$_upstream_name"
    require_arg "后端地址" "$_upstream_backend"
    validate_upstream_name "$_upstream_name"
    validate_backend "$_upstream_backend"

    # 检查 upstream 是否存在
    if ! _upstream_exists "$_upstream_name"; then
        die "upstream ${_upstream_name} 不存在"
    fi

    # 检查后端是否存在
    local _upstream_found=0
    local _upstream_in_block=0
    local _upstream_line
    while IFS= read -r _upstream_line; do
        if [[ "$_upstream_line" =~ ^upstream[[:space:]]+${_upstream_name}[[:space:]]*\{ ]]; then
            _upstream_in_block=1
        elif [[ "$_upstream_line" =~ ^\} ]] && [[ "$_upstream_in_block" -eq 1 ]]; then
            _upstream_in_block=0
        elif [[ "$_upstream_in_block" -eq 1 ]] && \
             echo "$_upstream_line" | grep -qE "^\s*server\s+${_upstream_backend}\s*;"; then
            _upstream_found=1
            break
        fi
    done < "$_UPSTREAM_FILE"

    if [[ "$_upstream_found" -eq 0 ]]; then
        log_info "后端 ${_upstream_backend} 不在 upstream ${_upstream_name} 中，无需操作"
        return 0
    fi

    acquire_lock

    # 备份
    backup_nginx_config "pre-upstream-remove-${_upstream_name}" > /dev/null

    # 预检
    log_step "预检: 验证当前 nginx 配置..."
    if ! nginx_test; then
        die "当前 nginx 配置存在问题，无法移除后端。请先修复配置"
    fi

    log_step "从 upstream ${_upstream_name} 移除后端: ${_upstream_backend}..."

    if is_dry_run; then
        log_info "[DRY-RUN] 将移除 server ${_upstream_backend}; 从 upstream ${_upstream_name}"
        return 0
    fi

    # 从 upstream 块内删除该 server 行
    sed -i "/^upstream\s\+${_upstream_name}\s\+{/,/^}/ {
        /server\s\+${_upstream_backend}\s*;/d
    }" "$_UPSTREAM_FILE" || die "移除后端失败"

    # 检查 upstream 块是否为空 (只剩 upstream NAME { 和 } 之间没有 server)
    local _upstream_block_content
    _upstream_block_content=$(sed -n "/^upstream\s\+${_upstream_name}\s\+{/,/^}/ {
        /^upstream/d
        /^}/d
        /server/!d
        p
    }" "$_UPSTREAM_FILE" 2>/dev/null)

    if [[ -z "$_upstream_block_content" ]]; then
        log_info "upstream ${_upstream_name} 已无后端，移除整个 upstream 块..."
        sed -i "/^upstream\s\+${_upstream_name}\s\+{/,/^}/d" "$_UPSTREAM_FILE" 2>/dev/null
        # 清理多余空行
        sed -i '/^$/N;/^\n$/d' "$_UPSTREAM_FILE" 2>/dev/null
        log_ok "upstream ${_upstream_name} 已移除 (无后端)"
    fi

    # 后检
    log_step "后检: 验证 nginx 配置..."
    if ! nginx_test; then
        log_error "移除后端后配置测试失败，请手动检查"
        die "nginx 配置验证失败。请检查配置: ${_UPSTREAM_FILE}"
    fi

    if [[ -n "$_upstream_block_content" ]]; then
        log_ok "后端 ${_upstream_backend} 已从 upstream ${_upstream_name} 移除"
    fi
}

# -----------------------------
# _upstream_list - 列出所有 upstream 及后端
# -----------------------------
_upstream_list() {
    _upstream_ensure_file

    if [[ ! -f "$_UPSTREAM_FILE" ]] || [[ ! -s "$_UPSTREAM_FILE" ]]; then
        log_info "暂无 upstream 配置"
        return 0
    fi

    print_banner "Upstream 负载均衡池列表"

    local _upstream_found=0
    local _upstream_current=""
    local _upstream_has_server=0
    local _upstream_line

    while IFS= read -r _upstream_line; do
        # 匹配 upstream 块开始
        if [[ "$_upstream_line" =~ ^upstream[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*\{ ]]; then
            _upstream_current="${BASH_REMATCH[1]}"
            _upstream_found=1
            _upstream_has_server=0
            echo -e "  ${COLOR_BOLD}${COLOR_CYAN}upstream ${_upstream_current}${COLOR_RESET}"
            continue
        fi

        # 匹配 upstream 块结束
        if [[ "$_upstream_line" =~ ^\} ]] && [[ -n "$_upstream_current" ]]; then
            if [[ "$_upstream_has_server" -eq 0 ]]; then
                echo -e "    ${COLOR_YELLOW}(空 - 无后端)${COLOR_RESET}"
            fi
            _upstream_current=""
            echo
            continue
        fi

        # 匹配 server 行
        if [[ -n "$_upstream_current" ]] && [[ "$_upstream_line" =~ ^[[:space:]]*server[[:space:]]+([^;]+)\; ]]; then
            local _upstream_server="${BASH_REMATCH[1]}"
            # 去除前后空格
            _upstream_server="$(echo "$_upstream_server" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
            echo -e "    ${COLOR_GREEN}●${COLOR_RESET} ${_upstream_server}"
            _upstream_has_server=1
        fi
    done < "$_UPSTREAM_FILE"

    if [[ "$_upstream_found" -eq 0 ]]; then
        log_info "暂无 upstream 配置"
    fi
}

# -----------------------------
# 主入口 (由 nginx-tools 调用)
# -----------------------------
_upstream_main() {
    local _upstream_subcmd="${1:-help}"
    shift 2>/dev/null || true

    case "$_upstream_subcmd" in
        create|new)
            _upstream_create "$@"
            ;;
        add)
            _upstream_add "$@"
            ;;
        remove|rm|del|delete)
            _upstream_remove "$@"
            ;;
        list|ls)
            _upstream_list "$@"
            ;;
        help|--help|-h)
            _upstream_help
            ;;
        *)
            log_error "未知子命令: ${_upstream_subcmd}"
            _upstream_help
            return 1
            ;;
    esac
}
