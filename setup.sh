#!/bin/bash

# License Server 一键部署脚本
# 使用方法: ./setup.sh

set -e

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "======================================"
echo "  License Server 部署工具"
echo "======================================"
echo ""

# 检查是否在 license-server 目录
if [ ! -f "package.json" ]; then
  echo "❌ 错误: 请在 license-server 目录下运行此脚本"
  exit 1
fi

# 1. 检查环境变量文件
echo "📋 步骤 1: 检查环境变量配置"
if [ ! -f ".env" ]; then
  echo "⚠️  未找到 .env 文件，从 env.example 复制..."
  cp env.example .env
  echo "✅ 已创建 .env 文件，请编辑配置后重新运行此脚本"
  echo ""
  echo "必须配置的项目："
  echo "  - DATABASE_URL: 数据库连接地址"
  echo "  - JWT_SECRET: JWT密钥（至少32位随机字符串）"
  echo "  - ADMIN_EMAIL: 管理员邮箱"
  echo "  - ADMIN_PASSWORD: 管理员密码"
  echo ""
  exit 1
fi

# 加载环境变量
set -a
source .env
set +a

# 2. 验证必需的环境变量
echo "✅ .env 文件已存在"
echo ""
echo "📋 步骤 2: 验证环境变量"

REQUIRED_VARS=("DATABASE_URL" "JWT_SECRET" "ADMIN_EMAIL" "ADMIN_PASSWORD")
MISSING_VARS=()

for VAR in "${REQUIRED_VARS[@]}"; do
  if [ -z "${!VAR}" ]; then
    MISSING_VARS+=("$VAR")
  fi
done

if [ ${#MISSING_VARS[@]} -ne 0 ]; then
  echo "❌ 错误: 以下环境变量未设置:"
  for VAR in "${MISSING_VARS[@]}"; do
    echo "  - $VAR"
  done
  echo "请编辑 .env 文件并设置这些变量"
  exit 1
fi

echo "✅ 环境变量验证通过"
echo ""

# 3. 生成 License 密钥对（如果不存在）
echo "📋 步骤 3: 检查 License 密钥对"
if [ -z "$LICENSE_PRIVATE_KEY" ] || [ -z "$LICENSE_PUBLIC_KEY" ]; then
  echo "⚠️  未找到 License 密钥对，正在生成..."
  
  # 检查 Node.js
  if ! command -v node &> /dev/null; then
    echo "❌ 错误: 未安装 Node.js"
    exit 1
  fi
  
  # 生成密钥对
  node > /tmp/keys.txt << 'EOF'
const crypto = require('crypto');
const { publicKey, privateKey } = crypto.generateKeyPairSync('rsa', {
  modulusLength: 2048,
  publicKeyEncoding: { type: 'spki', format: 'der' },
  privateKeyEncoding: { type: 'pkcs8', format: 'der' }
});
console.log('LICENSE_PRIVATE_KEY=' + privateKey.toString('base64'));
console.log('LICENSE_PUBLIC_KEY=' + publicKey.toString('base64'));
EOF
  
  # 追加到 .env 文件
  echo "" >> .env
  echo "# 自动生成的 License 密钥对 ($(date))" >> .env
  cat /tmp/keys.txt >> .env
  rm /tmp/keys.txt
  
  echo "✅ License 密钥对已生成并保存到 .env"
else
  echo "✅ License 密钥对已存在"
fi
echo ""

# 4. 测试数据库连接
echo "📋 步骤 4: 测试数据库连接"

# 解析 DATABASE_URL
# mysql://user:pass@host:port/dbname
DB_URL="${DATABASE_URL}"
DB_USER=$(echo $DB_URL | sed -n 's|.*://\([^:]*\):.*|\1|p')
DB_PASS=$(echo $DB_URL | sed -n 's|.*://[^:]*:\([^@]*\)@.*|\1|p')
DB_HOST=$(echo $DB_URL | sed -n 's|.*@\([^:/]*\).*|\1|p')
DB_PORT=$(echo $DB_URL | sed -n 's|.*@[^:]*:\([^/]*\)/.*|\1|p')
DB_NAME=$(echo $DB_URL | sed -n 's|.*/\([^?]*\).*|\1|p')

# 如果没有指定端口，使用默认端口
if [ -z "$DB_PORT" ]; then
  DB_PORT="3306"
  DB_HOST=$(echo $DB_URL | sed -n 's|.*@\([^/]*\)/.*|\1|p')
fi

# 处理 host.docker.internal 的情况
if [ "$DB_HOST" = "host.docker.internal" ]; then
  TEST_HOST="127.0.0.1"
else
  TEST_HOST="$DB_HOST"
fi

echo "数据库信息:"
echo "  主机: $DB_HOST"
echo "  端口: $DB_PORT"
echo "  用户: $DB_USER"
echo "  数据库: $DB_NAME"
echo ""

# 检查 MySQL 客户端
if command -v mysql &> /dev/null; then
  echo "正在测试数据库连接..."
  if mysql -h"$TEST_HOST" -P"$DB_PORT" -u"$DB_USER" -p"$DB_PASS" -e "SELECT 1;" &> /dev/null; then
    echo "✅ 数据库连接成功"
    
    # 询问是否初始化数据库
    echo ""
    read -p "是否初始化数据库? (y/n) " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      # 查找 init-db.sql 文件
      if [ -f "init-db.sql" ]; then
        SQL_FILE="init-db.sql"
      elif [ -f "$SCRIPT_DIR/init-db.sql" ]; then
        SQL_FILE="$SCRIPT_DIR/init-db.sql"
      else
        echo "❌ 错误: 找不到 init-db.sql 文件"
        echo "   当前目录: $(pwd)"
        echo "   脚本目录: $SCRIPT_DIR"
        exit 1
      fi
      
      echo "正在初始化数据库..."
      echo "   使用 SQL 文件: $SQL_FILE"
      mysql -h"$TEST_HOST" -P"$DB_PORT" -u"$DB_USER" -p"$DB_PASS" < "$SQL_FILE"
      echo "✅ 数据库初始化完成"
    fi
  else
    echo "❌ 错误: 无法连接到数据库"
    echo "请检查:"
    echo "  1. MySQL 服务是否运行"
    echo "  2. DATABASE_URL 配置是否正确"
    echo "  3. 数据库用户权限是否正确"
    exit 1
  fi
else
  echo "⚠️  未找到 mysql 客户端，跳过数据库连接测试"
  echo "   应用启动时会自动创建表结构"
fi
echo ""

# 5. 安装依赖
echo "📋 步骤 5: 安装依赖"
if [ ! -d "node_modules" ]; then
  echo "正在安装后端依赖..."
  npm install --no-audit --no-fund
else
  echo "✅ 后端依赖已安装"
fi

if [ ! -d "admin/node_modules" ]; then
  echo "正在安装前端依赖..."
  cd admin && npm install --no-audit --no-fund && cd ..
else
  echo "✅ 前端依赖已安装"
fi
echo ""

# 6. 构建项目
echo "📋 步骤 6: 构建项目"

echo "正在编译后端..."
npm run build

echo "正在构建管理面板..."
cd admin && npm run build && cd ..

echo "✅ 项目构建完成"
echo ""

# 7. 启动服务
echo "======================================"
echo "  ✅ 部署完成！"
echo "======================================"
echo ""
echo "启动命令:"
echo "  开发模式: npm run dev"
echo "  生产模式: npm start"
echo ""
echo "访问地址:"
echo "  API: http://localhost:${PORT:-8080}"
echo "  管理后台: http://localhost:${PORT:-8080}/admin"
echo "  健康检查: http://localhost:${PORT:-8080}/healthz"
echo ""
echo "管理员账号:"
echo "  邮箱: $ADMIN_EMAIL"
echo "  密码: $ADMIN_PASSWORD"
echo ""

# 询问是否立即启动
read -p "是否立即启动服务? (y/n) " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
  echo "正在启动服务..."
  npm start
fi

