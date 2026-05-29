#!/usr/bin/env bash
# =====================================================
# modules/ssl.sh - SSL 证书管理模块 (acme.sh)
# =====================================================
# 子命令: issue, install, renew, list, help
# 用法:   nginx-tools ssl <subcommand> [args...]
# =====================================================

# -----------------------------
# 帮助信息
# -----------------------------
_ssl_help() {
    cat <<EOF
nginx-tools ssl - SSL 证书管理 (acme.sh + Let's Encrypt)

用法:
  nginx-tools ssl <subcommand> [args...]

可用子命令:
  issue <domain> [--ecc] [--keylength <256|384>]
      申请证书并自动安装到 nginx
      --ecc         使用 ECC 证书 (默认)
      --keylength   密钥长度: 256 (默认) 或 384

  install <domain>
      将已申请的证书安装到 nginx 路径 (不重新申请)

  renew [domain] [--force]
      续签证书。不指定域名则续签所有证书
      --force       强制续签 (即使未到期)

  list
      列出所有已申请的证书及到期时间

  help
      显示此帮助信息

示例:
  nginx-tools ssl issue example.com
  nginx-tools ssl issue example.com --ecc --keylength 384
  nginx-tools ssl install example.com
  nginx-tools ssl renew example.com
  nginx-tools ssl renew
  nginx-tools ssl list
EOF
}

# -----------------------------
# _ssl_find_acme - 检测 acme.sh 路径
# -----------------------------
_ssl_find_acme() {
    local _ssl_acme_paths=(
        "${HOME}/.acme.sh/acme.sh"
        "/root/.acme.sh/acme.sh"
        "/usr/local/bin/acme.sh"
    )
    local _ssl_path

    for _ssl_path in "${_ssl_acme_paths[@]}"; do
        if [[ -x "$_ssl_path" ]]; then
            echo "$_ssl_path"
            return 0
        fi
    done

    # 也尝试 PATH 中的 acme.sh（排除 alias/function）
    local _ssl_path_from_path
    if _ssl_path_from_path="$(type -P acme.sh 2>/dev/null)" && [[ -n "$_ssl_path_from_path" ]]; then
        echo "$_ssl_path_from_path"
        return 0
    fi

    return 1
}

# -----------------------------
# _ssl_acme_exec - 在 sudo 提权环境下安全执行 acme.sh
# -----------------------------
_ssl_acme_exec() {
    local _ssl_acme_path="$1"
    shift

    env \
        -u SUDO_USER \
        -u SUDO_UID \
        -u SUDO_GID \
        -u SUDO_COMMAND \
        bash "$_ssl_acme_path" "$@"
}

_ssl_require_acme() {
    local _ssl_acme_path
    _ssl_acme_path="$(_ssl_find_acme)" && {
        # 防御：确保路径是单行可执行文件（防止先前 stdout 污染）
        if [[ ! -f "$_ssl_acme_path" || ! -x "$_ssl_acme_path" ]]; then
            log_error "acme.sh 路径无效或不可执行: ${_ssl_acme_path}"
            return 1
        fi
        _ssl_acme_exec "$_ssl_acme_path" --set-default-ca --server letsencrypt >/dev/null 2>&1 || true
        echo "$_ssl_acme_path"
        return 0
    }

    log_warn "未检测到 acme.sh"
    if is_dry_run; then
        log_info "[DRY-RUN] 将安装 acme.sh: curl https://get.acme.sh | sh"
        echo "dry-run-acme.sh"
        return 0
    fi

    if ! confirm "是否安装 acme.sh？(curl https://get.acme.sh | sh)" "y"; then
        die "acme.sh 未安装，无法管理 SSL 证书"
    fi

    log_step "正在安装 acme.sh..."
    curl https://get.acme.sh | sh || die "acme.sh 安装失败"

    _ssl_acme_path="$(_ssl_find_acme)" || die "acme.sh 安装后仍无法找到"

    # 验证 acme.sh 可以正常运行（修复 shebang 问题）
    if ! _ssl_acme_exec "$_ssl_acme_path" --version &>/dev/null; then
        # acme.sh 安装时可能修改 shebang 导致无法直接执行
        # 尝试修复 shebang
        local _ssl_bash_path
        _ssl_bash_path="$(command -v bash)" || _ssl_bash_path="/usr/bin/env bash"
        sed -i "1s|^#!.*|#!${_ssl_bash_path}|" "$_ssl_acme_path"
        if ! _ssl_acme_exec "$_ssl_acme_path" --version &>/dev/null; then
            die "acme.sh 安装后无法运行，请手动检查: ${_ssl_acme_path}"
        fi
    fi

    # 切换默认 CA 为 Let's Encrypt（ZeroSSL 需要邮箱注册，Let's Encrypt 无需）
    _ssl_acme_exec "$_ssl_acme_path" --set-default-ca --server letsencrypt >/dev/null 2>&1 || true

    log_ok "acme.sh 已安装: ${_ssl_acme_path}"
    echo "$_ssl_acme_path"
}

# -----------------------------
# _ssl_check_nginx_ready - 前置检查
# -----------------------------
_ssl_check_nginx_ready() {
    local _ssl_domain="$1"

    # 检查站点存在且已启用
    local _ssl_sites_available _ssl_sites_enabled
    _ssl_sites_available="$(get_sites_available)"
    _ssl_sites_enabled="$(get_sites_enabled)"

    if [[ ! -f "${_ssl_sites_available}/${_ssl_domain}" ]]; then
        die "站点配置不存在: ${_ssl_sites_available}/${_ssl_domain}。请先创建站点: nginx-tools site add ${_ssl_domain}"
    fi

    if [[ ! -L "${_ssl_sites_enabled}/${_ssl_domain}" ]]; then
        die "站点未启用: ${_ssl_domain}。acme.sh --nginx 模式需要站点处于启用状态。请执行: nginx-tools site enable ${_ssl_domain}"
    fi

    # 检查 nginx 运行状态
    if ! nginx_is_running; then
        die "nginx 未运行，请先启动 nginx: systemctl start nginx"
    fi

    # 检查 nginx 配置有效
    if ! nginx_test; then
        die "nginx 配置存在错误，请先修复配置再申请证书"
    fi
}

# -----------------------------
# _ssl_issue - 申请证书
# -----------------------------
_ssl_issue() {
    local _ssl_domain=""
    local _ssl_ecc=1
    local _ssl_keylength="256"

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --ecc)
                _ssl_ecc=1
                shift
                ;;
            --keylength)
                require_arg "--keylength 的值" "${2:-}"
                _ssl_keylength="$2"
                shift 2
                ;;
            -*)
                die "未知选项: $1"
                ;;
            *)
                if [[ -z "$_ssl_domain" ]]; then
                    _ssl_domain="$1"
                else
                    die "多余的参数: $1"
                fi
                shift
                ;;
        esac
    done

    require_arg "域名" "$_ssl_domain"
    validate_domain "$_ssl_domain"

    # 验证 keylength
    if [[ "$_ssl_keylength" != "256" && "$_ssl_keylength" != "384" ]]; then
        die "无效的密钥长度: ${_ssl_keylength}。只支持 256 或 384"
    fi

    local _ssl_acme_path
    _ssl_acme_path="$(_ssl_require_acme)"

    # 前置检查
    _ssl_check_nginx_ready "$_ssl_domain"

    acquire_lock

    local _ssl_ssl_dir
    _ssl_ssl_dir="$(get_nginx_ssl_dir)/${_ssl_domain}"

    log_step "申请 SSL 证书: ${_ssl_domain} (EC-${_ssl_keylength})..."

    if is_dry_run; then
        log_info "[DRY-RUN] 将执行: ${_ssl_acme_path} --issue --nginx -d ${_ssl_domain} --keylength ec-${_ssl_keylength} --force"
        log_info "[DRY-RUN] 将安装证书到: ${_ssl_ssl_dir}/"
        return 0
    fi

    # 申请证书
    _ssl_acme_exec "$_ssl_acme_path" --issue \
        --nginx \
        -d "$_ssl_domain" \
        --keylength "ec-${_ssl_keylength}" \
        --force || die "证书申请失败: ${_ssl_domain}"

    log_ok "证书申请成功: ${_ssl_domain}"

    # 安装证书到 nginx 路径
    _ssl_install_to_nginx "$_ssl_acme_path" "$_ssl_domain" "$_ssl_ssl_dir"
}

# -----------------------------
# _ssl_install_to_nginx - 安装证书到 nginx 路径
# -----------------------------
_ssl_install_to_nginx() {
    local _ssl_acme_path="$1"
    local _ssl_domain="$2"
    local _ssl_ssl_dir="$3"

    ensure_dir "$_ssl_ssl_dir"

    log_step "安装证书到: ${_ssl_ssl_dir}/..."

    _ssl_acme_exec "$_ssl_acme_path" --install-cert --ecc \
        -d "$_ssl_domain" \
        --key-file       "${_ssl_ssl_dir}/privkey.pem" \
        --fullchain-file "${_ssl_ssl_dir}/fullchain.pem" \
        --cert-file      "${_ssl_ssl_dir}/cert.pem" \
        --reloadcmd      "nginx -t && (systemctl reload nginx 2>/dev/null || nginx -s reload)" \
        || die "证书安装失败: ${_ssl_domain}"

    log_ok "证书已安装:"
    echo "  私钥:     ${_ssl_ssl_dir}/privkey.pem"
    echo "  完整链:   ${_ssl_ssl_dir}/fullchain.pem"
    echo "  证书:     ${_ssl_ssl_dir}/cert.pem"

    # 显示到期时间
    _ssl_show_expiry "$_ssl_domain" "$_ssl_ssl_dir"
}

# -----------------------------
# _ssl_show_expiry - 显示证书到期时间
# -----------------------------
_ssl_show_expiry() {
    local _ssl_domain="$1"
    local _ssl_ssl_dir="$2"
    local _ssl_cert_file="${_ssl_ssl_dir}/fullchain.pem"

    if [[ ! -f "$_ssl_cert_file" ]]; then
        return 0
    fi

    local _ssl_expiry
    _ssl_expiry="$(openssl x509 -enddate -noout -in "$_ssl_cert_file" 2>/dev/null)" || return 0
    _ssl_expiry="${_ssl_expiry#notAfter=}"

    if [[ -n "$_ssl_expiry" ]]; then
        log_info "证书到期时间: ${_ssl_domain} -> ${_ssl_expiry}"
    fi
}

# -----------------------------
# _ssl_install - 安装已有证书
# -----------------------------
_ssl_install() {
    local _ssl_domain="$1"
    require_arg "域名" "$_ssl_domain"
    validate_domain "$_ssl_domain"

    local _ssl_acme_path
    _ssl_acme_path="$(_ssl_require_acme)"

    # 检查证书是否已申请
    if ! _ssl_acme_exec "$_ssl_acme_path" --list 2>/dev/null | grep -q "$_ssl_domain"; then
        die "未找到 ${_ssl_domain} 的证书。请先申请: nginx-tools ssl issue ${_ssl_domain}"
    fi

    acquire_lock

    local _ssl_ssl_dir
    _ssl_ssl_dir="$(get_nginx_ssl_dir)/${_ssl_domain}"

    if is_dry_run; then
        log_info "[DRY-RUN] 将安装证书 ${_ssl_domain} 到: ${_ssl_ssl_dir}/"
        return 0
    fi

    _ssl_install_to_nginx "$_ssl_acme_path" "$_ssl_domain" "$_ssl_ssl_dir"
}

# -----------------------------
# _ssl_renew - 续签证书
# -----------------------------
_ssl_renew() {
    local _ssl_domain=""
    local _ssl_force=""

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force)
                _ssl_force="--force"
                shift
                ;;
            -*)
                die "未知选项: $1"
                ;;
            *)
                if [[ -z "$_ssl_domain" ]]; then
                    _ssl_domain="$1"
                else
                    die "多余的参数: $1"
                fi
                shift
                ;;
        esac
    done

    local _ssl_acme_path
    _ssl_acme_path="$(_ssl_require_acme)"

    acquire_lock

    if [[ -n "$_ssl_domain" ]]; then
        validate_domain "$_ssl_domain"
        log_step "续签证书: ${_ssl_domain}..."

        if is_dry_run; then
            log_info "[DRY-RUN] 将执行: ${_ssl_acme_path} --renew --ecc -d ${_ssl_domain} ${_ssl_force}"
            return 0
        fi

        _ssl_acme_exec "$_ssl_acme_path" --renew --ecc \
            -d "$_ssl_domain" \
            $_ssl_force \
            || die "证书续签失败: ${_ssl_domain}"

        log_ok "证书已续签: ${_ssl_domain}"

        # 显示更新后的到期时间
        local _ssl_ssl_dir
        _ssl_ssl_dir="$(get_nginx_ssl_dir)/${_ssl_domain}"
        _ssl_show_expiry "$_ssl_domain" "$_ssl_ssl_dir"
    else
        log_step "续签所有证书..."

        if is_dry_run; then
            log_info "[DRY-RUN] 将执行: ${_ssl_acme_path} --renew --ecc ${_ssl_force}"
            return 0
        fi

        _ssl_acme_exec "$_ssl_acme_path" --renew --ecc \
            $_ssl_force \
            || die "证书续签失败"

        log_ok "所有证书续签完成"
    fi
}

# -----------------------------
# _ssl_list - 列出所有证书
# -----------------------------
_ssl_list() {
    local _ssl_acme_path
    _ssl_acme_path="$(_ssl_require_acme)"

    print_banner "SSL 证书列表"

    local _ssl_output
    _ssl_output="$(_ssl_acme_exec "$_ssl_acme_path" --list 2>&1)" || true

    if [[ -z "$_ssl_output" ]] || echo "$_ssl_output" | grep -q "no certs"; then
        log_info "暂无已申请的证书"
        return 0
    fi

    # 解析 acme.sh --list 输出
    local _ssl_has_certs=0
    local _ssl_line _ssl_domain _ssl_key_type _ssl_created

    while IFS= read -r _ssl_line; do
        # 跳过标题行和空行
        [[ "$_ssl_line" =~ ^Main_Domain ]] && continue
        [[ -z "$_ssl_line" ]] && continue

        _ssl_has_certs=1

        # 提取域名 (第一列)
        _ssl_domain="$(echo "$_ssl_line" | awk '{print $1}')"
        _ssl_key_type="$(echo "$_ssl_line" | awk '{print $4}')"
        _ssl_created="$(echo "$_ssl_line" | awk '{print $5}')"

        # 尝试获取到期时间
        local _ssl_ssl_dir _ssl_expiry_text
        _ssl_ssl_dir="$(get_nginx_ssl_dir)/${_ssl_domain}"
        _ssl_expiry_text=""

        if [[ -f "${_ssl_ssl_dir}/fullchain.pem" ]]; then
            _ssl_expiry_text="$(openssl x509 -enddate -noout -in "${_ssl_ssl_dir}/fullchain.pem" 2>/dev/null)" || true
            _ssl_expiry_text="${_ssl_expiry_text#notAfter=}"
        fi

        echo -e "  ${COLOR_BOLD}${_ssl_domain}${COLOR_RESET}"
        [[ -n "$_ssl_key_type" ]] && echo "    密钥类型: ${_ssl_key_type}"
        [[ -n "$_ssl_created" ]] && echo "    创建时间: ${_ssl_created}"
        [[ -n "$_ssl_expiry_text" ]] && echo "    到期时间: ${_ssl_expiry_text}"
        echo
    done <<< "$_ssl_output"

    if [[ "$_ssl_has_certs" -eq 0 ]]; then
        log_info "暂无已申请的证书"
    fi
}

# -----------------------------
# 主入口 (由 nginx-tools 调用)
# -----------------------------
_ssl_main() {
    local _ssl_subcmd="${1:-help}"
    shift 2>/dev/null || true

    case "$_ssl_subcmd" in
        issue)
            _ssl_issue "$@"
            ;;
        install|inst)
            _ssl_install "$@"
            ;;
        renew|ren)
            _ssl_renew "$@"
            ;;
        list|ls)
            _ssl_list "$@"
            ;;
        help|--help|-h)
            _ssl_help
            ;;
        *)
            log_error "未知子命令: ${_ssl_subcmd}"
            _ssl_help
            return 1
            ;;
    esac
}
