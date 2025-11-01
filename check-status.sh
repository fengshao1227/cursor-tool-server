#!/bin/bash

# License Server 状态检查脚本

set -e

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "======================================"
echo "  License Server 状态检查"
echo "======================================"
echo ""

# 加载环境变量
if [ -f ".env" ]; then
  set -a
  source .env
  set +a
fi

PORT="${PORT:-8080}"
BASE_URL="http://localhost:$PORT"

# 1. 检查服务是否运行
echo "📋 检查 1: 服务健康状态"
if curl -s "$BASE_URL/healthz" > /dev/null; then
  HEALTH=$(curl -s "$BASE_URL/healthz")
  echo "✅ 服务运行正常"
  echo "   响应: $HEALTH"
else
  echo "❌ 服务未运行或无法访问"
  echo "   请检查服务是否启动: npm start 或 npm run dev"
  exit 1
fi
echo ""

# 2. 检查数据库连接
echo "📋 检查 2: 数据库连接"
if [ -z "$DATABASE_URL" ]; then
  echo "⚠️  未设置 DATABASE_URL 环境变量"
else
  # 解析数据库信息
  DB_HOST=$(echo $DATABASE_URL | sed -n 's|.*@\([^:/]*\).*|\1|p')
  DB_PORT=$(echo $DATABASE_URL | sed -n 's|.*@[^:]*:\([^/]*\)/.*|\1|p')
  DB_NAME=$(echo $DATABASE_URL | sed -n 's|.*/\([^?]*\).*|\1|p')
  
  if [ -z "$DB_PORT" ]; then
    DB_PORT="3306"
    DB_HOST=$(echo $DATABASE_URL | sed -n 's|.*@\([^/]*\)/.*|\1|p')
  fi
  
  echo "   数据库: $DB_NAME"
  echo "   主机: $DB_HOST:$DB_PORT"
  
  # 如果有 mysql 客户端，检查表
  if command -v mysql &> /dev/null; then
    DB_USER=$(echo $DATABASE_URL | sed -n 's|.*://\([^:]*\):.*|\1|p')
    DB_PASS=$(echo $DATABASE_URL | sed -n 's|.*://[^:]*:\([^@]*\)@.*|\1|p')
    
    TEST_HOST="$DB_HOST"
    if [ "$DB_HOST" = "host.docker.internal" ]; then
      TEST_HOST="127.0.0.1"
    fi
    
    TABLES=$(mysql -h"$TEST_HOST" -P"$DB_PORT" -u"$DB_USER" -p"$DB_PASS" -D"$DB_NAME" -e "SHOW TABLES;" 2>/dev/null | grep -v "Tables_in_" || true)
    
    if [ -n "$TABLES" ]; then
      echo "✅ 数据库表已创建"
      echo ""
      echo "   现有表:"
      while IFS= read -r table; do
        COUNT=$(mysql -h"$TEST_HOST" -P"$DB_PORT" -u"$DB_USER" -p"$DB_PASS" -D"$DB_NAME" -e "SELECT COUNT(*) FROM $table;" 2>/dev/null | tail -n 1)
        echo "     - $table ($COUNT 条记录)"
      done <<< "$TABLES"
    else
      echo "⚠️  数据库表未创建，请运行初始化脚本"
    fi
  else
    echo "ℹ️  无法检查数据库表（未安装 mysql 客户端）"
  fi
fi
echo ""

# 3. 检查管理面板
echo "📋 检查 3: 管理面板"
if [ -d "admin/dist" ]; then
  FILE_COUNT=$(find admin/dist -type f | wc -l | tr -d ' ')
  echo "✅ 管理面板已构建 ($FILE_COUNT 个文件)"
  
  # 测试访问
  if curl -s "$BASE_URL/admin/" > /dev/null; then
    echo "✅ 管理面板可访问"
    echo "   地址: $BASE_URL/admin/"
  else
    echo "⚠️  管理面板无法访问"
  fi
else
  echo "❌ 管理面板未构建"
  echo "   请运行: cd admin && npm run build"
fi
echo ""

# 4. 检查环境变量
echo "📋 检查 4: 环境变量配置"

check_env() {
  local VAR_NAME=$1
  local VAR_VALUE="${!VAR_NAME}"
  local REQUIRED=$2
  
  if [ -z "$VAR_VALUE" ]; then
    if [ "$REQUIRED" = "true" ]; then
      echo "   ❌ $VAR_NAME: 未设置 (必需)"
      return 1
    else
      echo "   ⚠️  $VAR_NAME: 未设置 (可选)"
    fi
  else
    echo "   ✅ $VAR_NAME: 已设置"
  fi
  return 0
}

ERRORS=0

check_env "DATABASE_URL" "true" || ((ERRORS++))
check_env "JWT_SECRET" "true" || ((ERRORS++))
check_env "ADMIN_EMAIL" "true" || ((ERRORS++))
check_env "ADMIN_PASSWORD" "true" || ((ERRORS++))
check_env "LICENSE_PRIVATE_KEY" "false"
check_env "LICENSE_PUBLIC_KEY" "false"
check_env "ALLOW_ORIGIN" "false"

echo ""

# 5. 检查管理员账号
echo "📋 检查 5: 管理员账号"
if [ -n "$ADMIN_EMAIL" ]; then
  echo "   邮箱: $ADMIN_EMAIL"
  echo "   密码: $ADMIN_PASSWORD"
  echo "   ✅ 可使用此账号登录管理后台"
else
  echo "   ⚠️  未设置管理员账号"
fi
echo ""

# 总结
echo "======================================"
if [ $ERRORS -eq 0 ]; then
  echo "  ✅ 所有检查通过！"
else
  echo "  ⚠️  发现 $ERRORS 个问题"
fi
echo "======================================"
echo ""
echo "访问地址:"
echo "  管理后台: $BASE_URL/admin/"
echo "  API 文档: $BASE_URL/healthz"
echo ""

