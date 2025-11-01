#!/bin/bash

# License Server 自动部署脚本
# 
# 用法：
#   ./deploy.sh          # 自动 git pull 并部署
#   ./deploy.sh --no-git # 跳过 git pull，仅重新部署
#
# 功能：
#   1. 自动拉取最新代码（git pull）
#   2. 停止旧服务
#   3. 安装依赖
#   4. 编译后端 + 构建前端
#   5. 启动新服务
#   6. 健康检查

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "======================================"
echo "  License Server 自动部署"
echo "======================================"
echo ""

# 加载环境变量（如果有）
if [ -f ".env" ]; then
  set -a
  source .env
  set +a
fi

PORT="${PORT:-8080}"

# 解析命令行参数
SKIP_GIT=false
if [ "$1" = "--no-git" ]; then
  SKIP_GIT=true
fi

# 1. 更新代码（如果是 Git 仓库且未跳过）
if [ -d ".git" ] && [ "$SKIP_GIT" = false ]; then
  echo "📥 拉取最新代码..."
  
  # 检查是否有未提交的更改
  if ! git diff-index --quiet HEAD -- 2>/dev/null; then
    echo "⚠️  警告：有未提交的更改"
    echo ""
    git status --short
    echo ""
    read -p "是否继续部署? (y/n) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      echo "已取消部署"
      exit 1
    fi
  fi
  
  # 拉取最新代码
  git pull || {
    echo "❌ Git pull 失败"
    exit 1
  }
  
  echo "✅ 代码已更新"
  echo ""
else
  echo "ℹ️  不是 Git 仓库，跳过代码更新"
  echo ""
fi

# 2. 停止旧服务
echo "🔄 停止旧服务..."
pkill -f "node dist/index.js" 2>/dev/null && sleep 1 || echo "   没有运行中的服务"
echo ""

# 3. 安装/更新后端依赖
echo "📦 检查后端依赖..."
npm install --production=false --no-audit --no-fund
echo ""

# 4. 编译后端
echo "🔨 编译后端..."
npm run build
echo ""

# 5. 构建前端
echo "🎨 构建前端..."
cd admin

# 检查前端依赖
if [ ! -d "node_modules" ]; then
  echo "   安装前端依赖..."
  npm install --no-audit --no-fund
fi

# 清理旧构建
rm -rf dist

# 构建
npm run build

# 验证构建结果
if [ ! -f "dist/index.html" ]; then
  echo "❌ 错误：前端构建失败"
  exit 1
fi

cd ..
echo ""

# 6. 启动服务
echo "🚀 启动服务..."
nohup npm start > server.log 2>&1 &
SERVER_PID=$!
echo "   PID: $SERVER_PID"
echo ""

# 7. 等待启动
echo "⏳ 等待服务启动..."
sleep 3

# 8. 健康检查
echo "🏥 健康检查..."
MAX_RETRIES=5
RETRY=0

while [ $RETRY -lt $MAX_RETRIES ]; do
  if curl -s http://localhost:$PORT/healthz > /dev/null 2>&1; then
    echo "✅ 服务运行正常"
    break
  fi
  RETRY=$((RETRY+1))
  if [ $RETRY -lt $MAX_RETRIES ]; then
    echo "   等待中... ($RETRY/$MAX_RETRIES)"
    sleep 2
  fi
done

if [ $RETRY -eq $MAX_RETRIES ]; then
  echo "❌ 服务启动失败，请查看日志"
  echo ""
  echo "最近的日志:"
  tail -20 server.log
  exit 1
fi

echo ""

# 9. 显示 Git 信息
if [ -d ".git" ]; then
  COMMIT_INFO=$(git log -1 --pretty=format:"%h - %s (%cr)" 2>/dev/null || echo "unknown")
  echo "📌 当前版本: $COMMIT_INFO"
  echo ""
fi

# 10. 完成
echo "======================================"
echo "  ✅ 部署成功！"

echo ""
echo "服务信息:"
echo "  进程 PID: $SERVER_PID"
echo "  监听端口: $PORT"
echo ""
echo "访问地址:"
echo "  管理后台: http://your-server-ip:$PORT/admin/"
echo "  API文档: http://your-server-ip:$PORT/healthz"
echo ""
echo "管理员账号:"
echo "  邮箱: ${ADMIN_EMAIL:-admin@example.com}"
echo "  密码: ${ADMIN_PASSWORD:-******}"
echo ""
echo "常用命令:"
echo "  查看日志: tail -f server.log"
echo "  停止服务: pkill -f 'node dist/index.js'"
echo "  重新部署: ./deploy.sh"
echo "  检查状态: ./check-status.sh"
echo ""
