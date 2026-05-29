#!/usr/bin/env bash
# =====================================================
# modules/template.sh - 模板管理模块
# =====================================================
# 子命令: list, generate, help
# 用法:   nginx-tools template <subcommand> [args...]
# =====================================================

# -----------------------------
# 帮助信息
# -----------------------------
_template_help() {
    cat <<EOF
nginx-tools template - 模板管理 (站点配置模板)

用法:
  nginx-tools template <subcommand> [args...]

可用子命令:
  list                                 列出所有可用模板
  generate <domain> <template-name>    使用模板生成站点配置
  help                                 显示此帮助信息

可用模板:
  static         静态 HTML 站点
  wordpress      WordPress (PHP-FPM)
  nodebb         NodeBB 论坛 (默认端口 4567)
  reverse-proxy  通用反向代理 (占位配置)
  docker-app     Docker 容器应用

示例:
  nginx-tools template list
  nginx-tools template generate example.com static
  nginx-tools template generate blog.example.com wordpress
  nginx-tools template generate forum.example.com nodebb
  nginx-tools template generate app.example.com docker-app
EOF
}

# -----------------------------
# 模板描述定义
# -----------------------------
_template_describe() {
    local name="$1"
    case "$name" in
        static)        echo "静态 HTML 站点 (最小配置)" ;;
        wordpress)     echo "WordPress (PHP-FPM, Unix Socket)" ;;
        nodebb)        echo "NodeBB 论坛 (WebSocket 支持, 默认端口 4567)" ;;
        reverse-proxy) echo "通用反向代理 (占位配置, 建议使用 proxy add)" ;;
        docker-app)    echo "Docker 容器应用 (需指定端口)" ;;
        *)             echo "未知模板" ;;
    esac
}

# -----------------------------
# _template_list - 列出所有可用模板
# -----------------------------
_template_list() {
    print_banner "可用模板列表"

    local tpl
    for tpl in static wordpress nodebb reverse-proxy docker-app; do
        echo -e "  ${COLOR_CYAN}${tpl}${COLOR_RESET}"
        echo "    $(_template_describe "$tpl")"
    done
    echo
}

# -----------------------------
# _template_generate - 生成站点配置
# -----------------------------
_template_generate() {
    local domain="$1"
    local template_name="$2"

    require_arg "域名" "$domain"
    require_arg "模板名称" "$template_name"
    validate_domain "$domain"
    validate_site_name "$domain"

    # 验证模板名称
    case "$template_name" in
        static|wordpress|nodebb|reverse-proxy|docker-app)
            ;;
        *)
            die "未知模板: ${template_name}。可用模板: static, wordpress, nodebb, reverse-proxy, docker-app"
            ;;
    esac

    local sites_available
    sites_available="$(get_sites_available)"
    ensure_sites_enabled

    local config_file="${sites_available}/${domain}"

    # 检查配置是否已存在
    if [[ -f "$config_file" ]]; then
        die "站点配置已存在: ${config_file}。如需修改请先删除"
    fi

    acquire_lock

    # 备份当前环境
    backup_nginx_config "pre-template-${domain}" > /dev/null

    log_step "生成站点配置: ${domain} (模板: ${template_name})..."

    if is_dry_run; then
        log_info "[DRY-RUN] 将创建站点配置: ${config_file}"
        return 0
    fi

    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"

    # 根据模板生成配置 (使用单引号 heredoc 防止 nginx $变量被展开)
    case "$template_name" in
        static)
            cat <<'TEMPLATE_EOF' > "$config_file"
# nginx-tools:template=static
# nginx-tools:created=TIMESTAMP_PLACEHOLDER
# nginx-tools:type=site

server {
    listen 80;
    listen [::]:80;

    server_name DOMAIN_PLACEHOLDER;

    root /var/www/DOMAIN_PLACEHOLDER;
    index index.html index.htm;

    location / {
        try_files $uri $uri/ =404;
    }

    # 禁止访问隐藏文件
    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }
}
TEMPLATE_EOF
            ;;

        wordpress)
            cat <<'TEMPLATE_EOF' > "$config_file"
# nginx-tools:template=wordpress
# nginx-tools:created=TIMESTAMP_PLACEHOLDER
# nginx-tools:type=site

server {
    listen 80;
    listen [::]:80;

    server_name DOMAIN_PLACEHOLDER;

    root /var/www/DOMAIN_PLACEHOLDER;
    index index.php index.html index.htm;

    location / {
        try_files $uri $uri/ /index.php?$args;
    }

    # PHP-FPM 处理
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php-fpm.sock;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
    }

    # 禁止访问隐藏文件
    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }

    # 禁止访问 wp-config.php
    location ~* wp-config\.php$ {
        deny all;
    }
}
TEMPLATE_EOF
            ;;

        nodebb)
            cat <<'TEMPLATE_EOF' > "$config_file"
# nginx-tools:template=nodebb
# nginx-tools:created=TIMESTAMP_PLACEHOLDER
# nginx-tools:type=site

server {
    listen 80;
    listen [::]:80;

    server_name DOMAIN_PLACEHOLDER;

    client_max_body_size 100M;

    location / {
        proxy_pass http://127.0.0.1:4567;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 3600;
        proxy_send_timeout 3600;
    }
}
TEMPLATE_EOF
            ;;

        reverse-proxy)
            cat <<'TEMPLATE_EOF' > "$config_file"
# nginx-tools:template=reverse-proxy
# nginx-tools:created=TIMESTAMP_PLACEHOLDER
# nginx-tools:type=site

# 注意: 此为占位配置，建议使用以下命令添加反向代理:
#   nginx-tools proxy add <domain> <backend>
# 例如:
#   nginx-tools proxy add DOMAIN_PLACEHOLDER 127.0.0.1:8080

server {
    listen 80;
    listen [::]:80;

    server_name DOMAIN_PLACEHOLDER;

    location / {
        # 请将 UPSTREAM 替换为实际后端地址，或使用 proxy add 命令
        proxy_pass http://UPSTREAM;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
TEMPLATE_EOF
            ;;

        docker-app)
            local port=""
            # docker-app 需要端口参数
            # 从第三个参数获取端口
            port="$3"

            if [[ -z "$port" ]]; then
                # 如果没有提供端口参数，提示用户
                read -r -p "请输入 Docker 容器映射端口: " port
            fi

            validate_port "$port" "Docker 容器端口"

            cat <<TEMPLATE_EOF > "$config_file"
# nginx-tools:template=docker-app
# nginx-tools:created=${ts}
# nginx-tools:type=site

server {
    listen 80;
    listen [::]:80;

    server_name ${domain};

    location / {
        proxy_pass http://127.0.0.1:${port};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
TEMPLATE_EOF
            ;;
    esac

    # 替换占位符 (非 docker-app 模板使用占位符)
    if [[ "$template_name" != "docker-app" ]]; then
        sed -i "s/DOMAIN_PLACEHOLDER/${domain}/g" "$config_file"
        sed -i "s/TIMESTAMP_PLACEHOLDER/${ts}/g" "$config_file"
    fi

    log_ok "站点配置已创建: ${config_file}"

    # 提示启用
    echo
    log_info "如需启用站点，请执行:"
    echo "  nginx-tools site enable ${domain}"
}

# -----------------------------
# 主入口 (由 nginx-tools 调用)
# -----------------------------
_template_main() {
    local subcmd="${1:-help}"
    shift 2>/dev/null || true

    case "$subcmd" in
        list|ls)
            _template_list "$@"
            ;;
        generate|gen|create)
            _template_generate "$@"
            ;;
        help|--help|-h)
            _template_help
            ;;
        *)
            log_error "未知子命令: ${subcmd}"
            _template_help
            return 1
            ;;
    esac
}
