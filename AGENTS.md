# AGENTS.md

## What this is

Pure-Bash Ubuntu 24.04 server deployment toolkit. Main project is `nginx-tools/` — a modular, zero-dependency nginx CLI management tool. Four standalone scripts at root for Docker install, SSH hardening, SSH keepalive, Docker cleanup.

## Entry points

- `nginx-tools` — CLI binary (main entry). Module dispatcher at line 169.
- `nginx-tools.sh` — interactive menu wrapper (calls `nginx-tools` CLI under the hood).
- Standalone scripts: `install_docker.sh`, `secure-setup.sh`, `set-ssh-timeout.sh`, `docker_cleanup.sh`.

## Architecture

- `lib/common.sh` — logging, colors, root detection (`require_root` → `exec sudo bash "$0" "$@"`), dry-run wrapper `run_cmd`, file lock at `/var/run/nginx-tools.lock`, cleanup traps, config metadata via `# nginx-tools:KEY=VALUE` comments.
- `lib/nginx.sh` — nginx binary/path detection (parses `nginx -V`), config test/reload/restart/status. Loaded **after** common.sh.
- `lib/validation.sh` — domain/IP/port/upstream validation.
- `lib/backup-lib.sh` — backup/restore to `/var/backups/nginx-tools/`.
- `modules/*.sh` — each module exports `_{name}_main` and `_{name}_help`. Loaded and invoked dynamically by `nginx-tools` main dispatcher.
- `templates/*.conf` — nginx config templates (static, wordpress, nodebb, reverse-proxy, docker-app).
- `docker-compose/nodebb/` — NodeBB forum with Docker Compose (separate from nginx-tools).

## Critical conventions

- `set -euo pipefail` in nginx-tools scripts; `set -e` in standalone scripts.
- `lib/common.sh` intentionally omits `set -e` (controlled by entry point).
- All scripts auto-elevate via `sudo` if not root. **Never run directly as root** — run as normal user with sudo access.
- `run_cmd` must be used instead of direct execution to respect `--dry-run`.
- DRY_RUN=1 skips all destructive operations (lock, mkdir, nginx reload, file writes).
- Config validation: `nginx -t` runs before every reload/restart and after config changes. Failures trigger auto-rollback from backup.
- Modules must NOT use `exit` — return non-zero instead (the dispatcher handles flow).
- Word splitting for optional flags is intentional (`$ws_flag $ssl_flag` without quotes). ShellCheck SC2086 is suppressed in those spots.

## Commands

```
# Run as normal user (auto sudo)
./nginx-tools <command> <subcommand> [options]
./nginx-tools.sh                              # interactive menu

# Global options (before subcommand)
--dry-run   --verbose   --yes/-y   --help/-h   --version/-v

# Common operations
nginx-tools site add example.com --template static
nginx-tools proxy add app.example.com --upstream 127.0.0.1:3000 --ssl --websocket
nginx-tools ssl issue example.com --ecc
nginx-tools nginx reload

# Standalone scripts (all auto-sudo)
./install_docker.sh
./secure-setup.sh
./set-ssh-timeout.sh          # also: --show to view current config
./docker_cleanup.sh

# Docker Compose
cd docker-compose/nodebb && docker compose up -d

# Dev symlink install
sudo ln -sf $(pwd)/nginx-tools /usr/local/bin/nginx-tools
```

## Dependencies

- nginx, sudo (required)
- acme.sh (required only for `nginx-tools ssl` commands)
- systemd (optional — falls back to direct nginx binary)
- docker, docker compose (for docker-compose/nodebb/ and docker_cleanup.sh)

## Environment variables

`NGINX_TOOLS_ROOT`, `NGINX_TOOLS_DRY_RUN`, `NGINX_TOOLS_VERBOSE`, `NGINX_TOOLS_YES`, `NGINX_TOOLS_BACKUP_RETENTION` (default 30 days).

## Testing / CI

None. No Makefile, no tests, no CI config, no lint rules. This is a shell-script project with no build or test infrastructure.
