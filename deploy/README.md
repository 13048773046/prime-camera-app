# uosar.yosar.cloud 部署

这个目录只放部署配置，不含任何密码。域名已经解析到 `101.34.235.101`；
当前该 IP 的 443 证书与 `uosar.yosar.cloud` 不匹配，必须先签发正确证书，
否则 App/H5 的 HTTPS 请求会被系统拒绝。

## 1. 服务器准备

```bash
sudo adduser --system --group --home /opt/prime prime
sudo mkdir -p /opt/prime /etc/prime
sudo chown -R prime:prime /opt/prime
```

把仓库里的 `backend/` 同步到 `/opt/prime/backend`，然后：

```bash
sudo -u prime python3 -m venv /opt/prime/venv
sudo -u prime /opt/prime/venv/bin/pip install -r /opt/prime/backend/requirements.txt
sudo cp deploy/prime.env.example /etc/prime/prime.env
sudo chmod 600 /etc/prime/prime.env
sudo editor /etc/prime/prime.env
```

`/etc/prime/prime.env` 必须改三处：`PRIME_ADMIN_PASSWORD`、`PRIME_AUTH_SECRET`、
以及可选的 `AI_API_KEY`（接 DeepSeek 后 AI 口令会从规则升级成模型改写）。
`PRIME_ADMIN_USER=玉玲` 保持不变。

## 2. 启动 API

```bash
sudo cp deploy/prime.service /etc/systemd/system/prime.service
sudo systemctl daemon-reload
sudo systemctl enable --now prime
sudo systemctl status prime --no-pager
curl -s http://127.0.0.1:8791/health
```

## 3. Nginx + 证书

```bash
sudo cp deploy/nginx-uosar.yosar.cloud.conf /etc/nginx/sites-available/uosar.yosar.cloud
sudo ln -sf /etc/nginx/sites-available/uosar.yosar.cloud /etc/nginx/sites-enabled/uosar.yosar.cloud
sudo nginx -t
sudo systemctl reload nginx
sudo certbot --nginx -d uosar.yosar.cloud
sudo certbot renew --dry-run
```

证书签发成功后：

- 落地页：`https://uosar.yosar.cloud/`
- H5 相机：`https://uosar.yosar.cloud/h5/`
- 管理台：`https://uosar.yosar.cloud/admin/`
- 所有 App 接口：`https://uosar.yosar.cloud/ai_camera/v2`、`/app/config_doka` 等

## 4. 验收

```bash
curl -s https://uosar.yosar.cloud/health
curl -s -o /dev/null -w '%{http_code}\n' https://uosar.yosar.cloud/h5/
curl -s -o /dev/null -w '%{http_code}\n' https://uosar.yosar.cloud/admin/
```

App 端构建时固定使用：

```bash
flutter build ipa --release --dart-define=PRIME_API_BASE=https://uosar.yosar.cloud
```

## 5. 发版注意

- SQLite 数据库在 `/opt/prime/backend/prime.db`，升级代码前先备份。
- 管理台默认账号是 `玉玲`；第一次登录后立刻确认 `/etc/prime/prime.env` 里的密码不是示例值。
- 管理台 token 存在浏览器 localStorage；公共电脑用完退出。
- `AI_API_KEY` 为空时，AI 构图仍然可用，只是口令由本地规则生成；填入 DeepSeek Key 后走模型改写。
