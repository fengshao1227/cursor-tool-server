# License Server 部署指南

## 📦 首次部署

### 1. 准备环境

确保服务器已安装：
- Node.js 18+ 
- MySQL 5.7+
- Git

### 2. 克隆代码

```bash
git clone <your-repo-url> license-server
cd license-server
```

### 3. 配置环境变量

```bash
# 复制配置文件
cp env.example .env

# 编辑配置
nano .env
```

**必填项：**
```bash
DATABASE_URL=mysql://username:password@localhost:3306/license_db?timezone=Z
JWT_SECRET=your_random_secret_at_least_32_chars
ADMIN_EMAIL=admin@example.com
ADMIN_PASSWORD=your_password  # 至少4位
PORT=8080
```

### 4. 初始化数据库（可选）

```bash
# 如果需要手动创建数据库和表
mysql -u root -p < init-db.sql

# 或者让应用自动创建（推荐）
# 应用启动时会自动创建表
```

### 5. 首次部署

```bash
chmod +x deploy.sh
./deploy.sh
```

## 🔄 日常更新

每次本地推送代码后，在服务器上只需运行：

```bash
cd /path/to/license-server
./deploy.sh
```

**就这么简单！** 脚本会自动：
- ✅ 拉取最新代码（git pull）
- ✅ 停止旧服务
- ✅ 安装依赖
- ✅ 编译后端
- ✅ 构建前端
- ✅ 启动新服务
- ✅ 健康检查
- ✅ 显示当前版本

## 📋 常用命令

```bash
# 部署/重启
./deploy.sh

# 检查状态
./check-status.sh

# 查看日志
tail -f server.log

# 停止服务
pkill -f "node dist/index.js"

# 查看进程
ps aux | grep "node dist/index.js"
```

## 🐳 Docker 部署（可选）

如果使用 Docker：

```bash
# 首次部署
docker-compose up -d

# 更新部署
git pull
docker-compose build
docker-compose up -d

# 查看日志
docker-compose logs -f
```

## 🔧 故障排查

### 服务启动失败

```bash
# 查看完整日志
tail -50 server.log

# 检查端口占用
netstat -tlnp | grep 8080

# 手动测试
npm run build
npm start
```

### 前端页面空白

```bash
# 检查前端构建
ls -la admin/dist/
ls -la admin/dist/assets/

# 重新构建
cd admin
rm -rf dist
npm run build
cd ..
```

### 数据库连接失败

```bash
# 测试数据库连接
mysql -h localhost -u username -p

# 检查 .env 配置
cat .env | grep DATABASE_URL
```

## 📱 访问地址

部署成功后访问：

- **管理后台**: `http://your-server-ip:8080/admin/`
- **健康检查**: `http://your-server-ip:8080/healthz`
- **API**: `http://your-server-ip:8080/v1/`

## 🔐 默认账号

使用 `.env` 中配置的账号登录：
- 邮箱: `ADMIN_EMAIL`
- 密码: `ADMIN_PASSWORD`

## 📝 生产环境建议

1. **使用 PM2 管理进程**（推荐）
```bash
npm install -g pm2
pm2 start npm --name license-server -- start
pm2 save
pm2 startup
```

2. **配置 Nginx 反向代理**
```nginx
server {
    listen 80;
    server_name your-domain.com;
    
    location / {
        proxy_pass http://localhost:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
```

3. **配置 HTTPS（使用 Let's Encrypt）**
```bash
certbot --nginx -d your-domain.com
```

4. **定期备份数据库**
```bash
# 创建备份脚本
cat > backup.sh << 'EOF'
#!/bin/bash
DATE=$(date +%Y%m%d_%H%M%S)
mysqldump -u root -p license_db > backup_$DATE.sql
EOF

chmod +x backup.sh

# 添加到 crontab（每天凌晨2点备份）
crontab -e
0 2 * * * /path/to/backup.sh
```

## 🆘 获取帮助

如有问题：
1. 查看日志：`tail -f server.log`
2. 运行状态检查：`./check-status.sh`
3. 查看完整文档：`README.md`

