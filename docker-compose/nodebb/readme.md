#   目录结构：

```
  docker-compose/nodebb/
  ├── Dockerfile          多阶段构建, git clone NodeBB v4.x
  ├── docker-compose.yml  nodebb + mongo 两个 service
  ├── entrypoint.sh       等 mongo → 首启生成 setup.json → 启动
  ├── mongo-init.sh       建 NodeBB 业务用户
  ├── .env.example        密码模板
  └── .gitignore          忽略 .env 与 data/
```

#   使用流程：

``` sh
cd ./myscript/docker-compose/nodebb
cp .env.example .env
```
 编辑 .env, 把所有 changeme-* 改成强密码

```sh
  docker compose up -d --build
  docker compose logs -f nodebb   # 首次会执行 setup, 约 1-3 分钟
```
  启动后访问 http://localhost:4567，用 .env 里的 ADMIN_USER / ADMIN_PASS 登录。

  关键设计说明：
  - ./data/config 暴露 config.json，改完重启 nodebb 容器生效
  - ./data/uploads 是用户上传（头像、附件），需要备份
  - ./data/mongo 是 MongoDB 数据
  - build 和 node_modules 故意没有绑到宿主机——绑空目录会把镜像内容遮掉导致启动失败；compose 文件里已注释说明
  - NODEBB_VERSION 在 .env 里可改（默认 v4.x），换分支或 tag 重新 --build 即可
  - mongo 用了 healthcheck + depends_on: service_healthy，nodebb 容器会等 mongo 真正就绪再启
  - setup.json 用完即删（含明文密码）

  重置数据库重装：

```sh
docker compose down && rm -rf ./data && docker compose up -d --build
```