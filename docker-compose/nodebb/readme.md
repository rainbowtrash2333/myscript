# NodeBB Docker

按官方 Ubuntu 安装文档 (https://docs.nodebb.org/installing/os/ubuntu/) 容器化:
node:lts → git clone NodeBB v4.x → npm install → setup → start, MongoDB 独立服务.

## 目录结构

```
docker-compose/nodebb/
├── Dockerfile          多阶段构建 (node:lts -> node:lts-slim), git clone v4.x
├── docker-compose.yml  nodebb + mongo
├── entrypoint.sh       等 mongo -> 首启生成 setup.json -> nodebb start
├── mongo-init.sh       建 NodeBB 业务用户
├── .env.example        密码模板
└── .gitignore          忽略 .env 与 data/
```

## 使用

```sh
cd ./docker-compose/nodebb
cp .env.example .env
# 编辑 .env, 把所有 changeme-* 改成强密码
docker compose up -d --build
docker compose logs -f nodebb   # 首启会跑 setup, 约 1-3 分钟
```

启动后访问 http://localhost:4567, 用 `.env` 里的 `ADMIN_USER` / `ADMIN_PASS` 登录.

## 数据卷

- `./data/config`   `config.json` 所在, 改完重启 nodebb 容器生效
- `./data/uploads`  用户上传 (头像、附件), 需要备份
- `./data/mongo`    MongoDB 数据

`build` 与 `node_modules` 故意没绑宿主机 — 绑空目录会把镜像内容遮掉导致启动失败.

## 切换 NodeBB 版本

在 `.env` 改 `NODEBB_VERSION` (默认 `v4.x`), 然后 `docker compose up -d --build`.

## 重置

```sh
docker compose down && rm -rf ./data && docker compose up -d --build
```
