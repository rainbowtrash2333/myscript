#!/usr/bin/env bash
# =====================================================
# modules/nginx.sh - nginx 管理模块
# =====================================================
# 子命令: reload, restart, test, status, help
# 用法:   nginx-tools nginx <subcommand>
# =====================================================

# -----------------------------
# 帮助信息
# -----------------------------
_nginx_help() {
    cat <<EOF
nginx-tools nginx - nginx 服务管理

用法:
  nginx-tools nginx <subcommand>

可用子命令:
  reload    重载 nginx 配置 (平滑重载，不中断连接)
  restart   重启 nginx 服务 (会中断连接，需确认)
  test      测试 nginx 配置文件语法
  status    显示 nginx 运行状态和版本信息
  help      显示此帮助信息

示例:
  nginx-tools nginx reload
  nginx-tools nginx test
  nginx-tools nginx status
EOF
}

# -----------------------------
# reload - 重载配置
# -----------------------------
_nginx_reload() {
    acquire_lock
    log_step "正在重载 nginx 配置..."
    nginx_reload
}

# -----------------------------
# restart - 重启服务
# -----------------------------
_nginx_restart() {
    if ! nginx_is_running; then
        log_warn "nginx 当前未运行，将直接启动"
    fi

    if ! confirm "确认重启 nginx？这将中断所有活跃连接" "n"; then
        log_info "已取消重启"
        return 0
    fi

    acquire_lock
    log_step "正在重启 nginx..."
    nginx_restart
}

# -----------------------------
# test - 配置测试
# -----------------------------
_nginx_test() {
    log_step "测试 nginx 配置..."
    nginx_test
}

# -----------------------------
# status - 运行状态
# -----------------------------
_nginx_status() {
    print_banner "nginx 状态"
    nginx_status

    if has_systemd; then
        echo
        print_separator "-"
        echo "进程详情:"
        ps aux 2>/dev/null | grep "[n]ginx" || echo "(无 nginx 进程)"
    fi
}

# -----------------------------
# 主入口 (由 nginx-tools 调用)
# -----------------------------
_nginx_main() {
    local subcmd="${1:-help}"
    shift 2>/dev/null || true

    case "$subcmd" in
        reload)
            _nginx_reload "$@"
            ;;
        restart)
            _nginx_restart "$@"
            ;;
        test)
            _nginx_test "$@"
            ;;
        status)
            _nginx_status "$@"
            ;;
        help|--help|-h)
            _nginx_help
            ;;
        *)
            log_error "未知子命令: ${subcmd}"
            _nginx_help
            return 1
            ;;
    esac
}
