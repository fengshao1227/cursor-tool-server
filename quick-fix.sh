#!/bin/bash

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  License Server 快速修复脚本${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# 检测 docker-compose 命令
DOCKER_COMPOSE="docker compose"
if ! docker compose version &> /dev/null; then
    DOCKER_COMPOSE="docker-compose"
fi

echo -e "${YELLOW}步骤 1/5: 停止并清理现有容器${NC}"
$DOCKER_COMPOSE down -v 2>/dev/null || true
docker rm -f license-server 2>/dev/null || true
echo -e "${GREEN}✓ 清理完成${NC}"
echo ""

echo -e "${YELLOW}步骤 2/5: 检查 .env 文件${NC}"
if [ ! -f .env ]; then
    echo -e "${YELLOW}未找到 .env 文件，正在从模板创建...${NC}"
    cp env.example .env
    
    # 生成随机密码
    MYSQL_PASS=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 24)
    JWT_SECRET=$(openssl rand -base64 48)
    ADMIN_PASS=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 16)
    
    # 更新 .env 文件（兼容 macOS 和 Linux）
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        sed -i '' "s/your_strong_mysql_password_here/$MYSQL_PASS/" .env
        sed -i '' "s/your_jwt_secret_at_least_32_chars_long_random_string/$JWT_SECRET/" .env
        sed -i '' "s/your_admin_password_here/$ADMIN_PASS/" .env
        sed -i '' "s/admin@example.com/admin@localhost/" .env
    else
        # Linux
        sed -i "s/your_strong_mysql_password_here/$MYSQL_PASS/" .env
        sed -i "s/your_jwt_secret_at_least_32_chars_long_random_string/$JWT_SECRET/" .env
        sed -i "s/your_admin_password_here/$ADMIN_PASS/" .env
        sed -i "s/admin@example.com/admin@localhost/" .env
    fi
    
    echo -e "${GREEN}✓ .env 文件已创建${NC}"
    echo ""
    echo -e "${BLUE}自动生成的凭据：${NC}"
    echo "  MySQL Root 密码: $MYSQL_PASS"
    echo "  管理员邮箱: admin@localhost"
    echo "  管理员密码: $ADMIN_PASS"
    echo ""
    echo -e "${YELLOW}请妥善保存这些信息！${NC}"
    echo ""
else
    echo -e "${GREEN}✓ .env 文件已存在${NC}"
fi

# 验证必需的环境变量
source .env

# 检查数据库配置（DATABASE_URL 或 MYSQL_ROOT_PASSWORD 至少设置一个）
if [ -z "$DATABASE_URL" ] && [ -z "$MYSQL_ROOT_PASSWORD" ]; then
    echo -e "${RED}错误: 请设置 DATABASE_URL（远程 MySQL）或 MYSQL_ROOT_PASSWORD（本地 MySQL）${NC}"
    echo "请编辑 .env 文件并设置 DATABASE_URL 或 MYSQL_ROOT_PASSWORD"
    exit 1
fi

if [ -z "$JWT_SECRET" ] || [ ${#JWT_SECRET} -lt 32 ]; then
    echo -e "${RED}错误: JWT_SECRET 未设置或长度不足32位${NC}"
    exit 1
fi

if [ -z "$ADMIN_EMAIL" ] || [ -z "$ADMIN_PASSWORD" ]; then
    echo -e "${RED}错误: ADMIN_EMAIL 或 ADMIN_PASSWORD 未设置${NC}"
    exit 1
fi

echo -e "${GREEN}✓ 环境变量验证通过${NC}"
echo ""

echo -e "${YELLOW}步骤 3/5: 生成 License 密钥对${NC}"
if [ -z "$LICENSE_PRIVATE_KEY" ] || [ -z "$LICENSE_PUBLIC_KEY" ]; then
    if command -v node &> /dev/null; then
        echo "正在生成 RSA 密钥对..."
        KEYS=$(node -e "
            const crypto = require('crypto');
            const { publicKey, privateKey } = crypto.generateKeyPairSync('rsa', {
                modulusLength: 2048,
                publicKeyEncoding: { type: 'spki', format: 'pem' },
                privateKeyEncoding: { type: 'pkcs8', format: 'pem' }
            });
            console.log(JSON.stringify({
                private: Buffer.from(privateKey).toString('base64'),
                public: Buffer.from(publicKey).toString('base64')
            }));
        ")
        
        PRIVATE_KEY=$(echo $KEYS | node -e "console.log(JSON.parse(require('fs').readFileSync(0, 'utf-8')).private)")
        PUBLIC_KEY=$(echo $KEYS | node -e "console.log(JSON.parse(require('fs').readFileSync(0, 'utf-8')).public)")
        
        # 追加到 .env 文件
        echo "" >> .env
        echo "# 自动生成的 License 密钥对 ($(date))" >> .env
        echo "LICENSE_PRIVATE_KEY=$PRIVATE_KEY" >> .env
        echo "LICENSE_PUBLIC_KEY=$PUBLIC_KEY" >> .env
        
        echo -e "${GREEN}✓ License 密钥对已生成${NC}"
    else
        echo -e "${YELLOW}⚠ Node.js 未安装，跳过密钥生成（服务启动时会自动生成）${NC}"
    fi
else
    echo -e "${GREEN}✓ License 密钥对已存在${NC}"
fi
echo ""

echo -e "${YELLOW}步骤 4/5: 构建并启动服务${NC}"
echo "正在构建 Docker 镜像..."
$DOCKER_COMPOSE build --no-cache

echo ""
echo "正在启动服务..."
$DOCKER_COMPOSE up -d

echo ""
echo "等待 License Server 启动..."
sleep 5

echo ""
echo -e "${YELLOW}步骤 5/5: 健康检查${NC}"
MAX_RETRIES=30
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if curl -f http://localhost:${PORT:-8080}/healthz > /dev/null 2>&1; then
        echo -e "${GREEN}✓ 服务健康检查通过${NC}"
        break
    fi
    
    RETRY_COUNT=$((RETRY_COUNT + 1))
    echo "等待服务启动... ($RETRY_COUNT/$MAX_RETRIES)"
    sleep 2
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo -e "${RED}✗ 服务启动失败或健康检查超时${NC}"
    echo ""
    echo "License Server 日志:"
    $DOCKER_COMPOSE logs license-server
    exit 1
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  修复完成！服务已成功启动${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "服务信息:"
echo "  - API 地址: http://localhost:${PORT:-8080}"
echo "  - 健康检查: http://localhost:${PORT:-8080}/healthz"
echo ""
echo "管理员账号:"
echo "  - 邮箱: $ADMIN_EMAIL"
echo "  - 密码: $ADMIN_PASSWORD"
echo ""
echo ""
echo "常用命令:"
echo "  - 查看日志: $DOCKER_COMPOSE logs -f"
echo "  - 查看状态: $DOCKER_COMPOSE ps"
echo "  - 停止服务: $DOCKER_COMPOSE down"
echo "  - 重启服务: $DOCKER_COMPOSE restart"
echo ""
echo -e "${BLUE}测试服务:${NC}"
echo "  curl http://localhost:${PORT:-8080}/healthz"
echo ""

