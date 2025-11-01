#!/bin/bash

# Docker 构建和部署脚本

set -e

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "======================================"
echo "  License Server Docker 部署"
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
  echo "❌ 错误: 未找到 .env 文件"
  echo "请先复制 env.example 到 .env 并配置"
  exit 1
fi

echo "✅ .env 文件已存在"
echo ""

# 2. 检查 Docker
echo "📋 步骤 2: 检查 Docker 环境"
if ! command -v docker &> /dev/null; then
  echo "❌ 错误: 未安装 Docker"
  exit 1
fi

if ! command -v docker-compose &> /dev/null; then
  echo "❌ 错误: 未安装 docker-compose"
  exit 1
fi

echo "✅ Docker 环境正常"
echo ""

# 3. 停止旧容器
echo "📋 步骤 3: 停止旧容器"
if docker ps -a | grep -q "license-server"; then
  echo "正在停止旧容器..."
  docker-compose down
fi
echo "✅ 旧容器已停止"
echo ""

# 4. 构建镜像
echo "📋 步骤 4: 构建 Docker 镜像"
docker-compose build --no-cache
echo "✅ 镜像构建完成"
echo ""

# 5. 启动服务
echo "📋 步骤 5: 启动服务"
docker-compose up -d
echo "✅ 服务已启动"
echo ""

# 6. 等待服务就绪
echo "📋 步骤 6: 等待服务就绪"
sleep 5

# 加载环境变量
set -a
source .env
set +a
PORT="${PORT:-8080}"

# 检查健康状态
MAX_RETRIES=30
RETRY=0

while [ $RETRY -lt $MAX_RETRIES ]; do
  if curl -s "http://localhost:$PORT/healthz" > /dev/null 2>&1; then
    echo "✅ 服务启动成功"
    break
  fi
  
  RETRY=$((RETRY+1))
  echo -n "."
  sleep 1
done

if [ $RETRY -eq $MAX_RETRIES ]; then
  echo ""
  echo "❌ 错误: 服务启动超时"
  echo "查看日志: docker-compose logs -f"
  exit 1
fi

echo ""
echo ""

# 7. 显示日志
echo "📋 步骤 7: 容器日志 (最近 20 行)"
echo "--------------------------------------"
docker-compose logs --tail=20
echo "--------------------------------------"
echo ""

# 完成
echo "======================================"
echo "  ✅ 部署完成！"
echo "======================================"
echo ""
echo "服务信息:"
echo "  容器名: license-server"
echo "  端口: $PORT"
echo ""
echo "访问地址:"
echo "  管理后台: http://localhost:$PORT/admin/"
echo "  健康检查: http://localhost:$PORT/healthz"
echo ""
echo "常用命令:"
echo "  查看日志: docker-compose logs -f"
echo "  重启服务: docker-compose restart"
echo "  停止服务: docker-compose down"
echo "  进入容器: docker exec -it license-server sh"
echo ""

