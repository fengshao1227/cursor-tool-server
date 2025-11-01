#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  License Server 配置验证${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

ERRORS=0
WARNINGS=0

# 检测 docker-compose 命令
DOCKER_COMPOSE="docker compose"
if ! docker compose version &> /dev/null; then
    DOCKER_COMPOSE="docker-compose"
fi

# 1. 检查 Docker
echo -e "${YELLOW}[1/7] 检查 Docker...${NC}"
if command -v docker &> /dev/null; then
    DOCKER_VERSION=$(docker --version)
    echo -e "${GREEN}✓ Docker 已安装: $DOCKER_VERSION${NC}"
else
    echo -e "${RED}✗ Docker 未安装${NC}"
    ERRORS=$((ERRORS + 1))
fi
echo ""

# 2. 检查 Docker Compose
echo -e "${YELLOW}[2/7] 检查 Docker Compose...${NC}"
if command -v docker-compose &> /dev/null || docker compose version &> /dev/null; then
    COMPOSE_VERSION=$($DOCKER_COMPOSE version 2>/dev/null || echo "unknown")
    echo -e "${GREEN}✓ Docker Compose 已安装: $COMPOSE_VERSION${NC}"
else
    echo -e "${RED}✗ Docker Compose 未安装${NC}"
    ERRORS=$((ERRORS + 1))
fi
echo ""

# 3. 检查 .env 文件
echo -e "${YELLOW}[3/7] 检查 .env 文件...${NC}"
if [ -f .env ]; then
    echo -e "${GREEN}✓ .env 文件存在${NC}"
    
    # 加载环境变量
    source .env
    
    # 检查必需变量
    # 注意: 使用远程 MySQL 时，MYSQL_ROOT_PASSWORD 可能不需要设置
    # 数据库连接信息通过 DATABASE_URL 配置
    if [ -z "$DATABASE_URL" ]; then
        echo -e "${YELLOW}  ⚠ DATABASE_URL 未设置（如果使用远程 MySQL，请设置此变量）${NC}"
        WARNINGS=$((WARNINGS + 1))
    else
        echo -e "${GREEN}  ✓ DATABASE_URL 已设置${NC}"
    fi
    
    if [ -z "$JWT_SECRET" ]; then
        echo -e "${RED}  ✗ JWT_SECRET 未设置${NC}"
        ERRORS=$((ERRORS + 1))
    elif [ ${#JWT_SECRET} -lt 32 ]; then
        echo -e "${YELLOW}  ⚠ JWT_SECRET 长度不足32位${NC}"
        WARNINGS=$((WARNINGS + 1))
    else
        echo -e "${GREEN}  ✓ JWT_SECRET 已设置${NC}"
    fi
    
    if [ -z "$ADMIN_EMAIL" ]; then
        echo -e "${RED}  ✗ ADMIN_EMAIL 未设置${NC}"
        ERRORS=$((ERRORS + 1))
    else
        echo -e "${GREEN}  ✓ ADMIN_EMAIL 已设置${NC}"
    fi
    
    if [ -z "$ADMIN_PASSWORD" ]; then
        echo -e "${RED}  ✗ ADMIN_PASSWORD 未设置${NC}"
        ERRORS=$((ERRORS + 1))
    else
        echo -e "${GREEN}  ✓ ADMIN_PASSWORD 已设置${NC}"
    fi
    
    if [ -z "$LICENSE_PRIVATE_KEY" ] || [ -z "$LICENSE_PUBLIC_KEY" ]; then
        echo -e "${YELLOW}  ⚠ License 密钥未设置（服务启动时会自动生成）${NC}"
        WARNINGS=$((WARNINGS + 1))
    else
        echo -e "${GREEN}  ✓ License 密钥已设置${NC}"
    fi
else
    echo -e "${RED}✗ .env 文件不存在${NC}"
    echo -e "${YELLOW}  提示: 运行 ./quick-fix.sh 自动创建${NC}"
    ERRORS=$((ERRORS + 1))
fi
echo ""

# 4. 检查 docker-compose.yml
echo -e "${YELLOW}[4/7] 检查 docker-compose.yml...${NC}"
if [ -f docker-compose.yml ]; then
    echo -e "${GREEN}✓ docker-compose.yml 存在${NC}"
    
    # 检查是否包含 license-server 服务
    if grep -q "license-server:" docker-compose.yml; then
        echo -e "${GREEN}  ✓ License Server 服务已定义${NC}"
    else
        echo -e "${RED}  ✗ License Server 服务未定义${NC}"
        ERRORS=$((ERRORS + 1))
    fi
else
    echo -e "${RED}✗ docker-compose.yml 不存在${NC}"
    ERRORS=$((ERRORS + 1))
fi
echo ""

# 5. 检查端口占用
echo -e "${YELLOW}[5/7] 检查端口占用...${NC}"
PORT=${PORT:-8080}

if lsof -Pi :$PORT -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠ 端口 $PORT 已被占用${NC}"
    lsof -Pi :$PORT -sTCP:LISTEN
    WARNINGS=$((WARNINGS + 1))
else
    echo -e "${GREEN}✓ 端口 $PORT 可用${NC}"
fi
echo ""

# 6. 检查容器状态
echo -e "${YELLOW}[6/7] 检查容器状态...${NC}"
if docker ps > /dev/null 2>&1; then
    if docker ps --format '{{.Names}}' | grep -q "license-server"; then
        STATUS=$(docker ps --filter "name=license-server" --format "{{.Status}}")
        echo -e "${GREEN}✓ license-server 容器运行中${NC}"
        echo -e "  状态: $STATUS"
    else
        echo -e "${YELLOW}⚠ license-server 容器未运行${NC}"
    fi
else
    echo -e "${YELLOW}⚠ 无法访问 Docker 守护进程${NC}"
    WARNINGS=$((WARNINGS + 1))
fi
echo ""

# 7. 健康检查
echo -e "${YELLOW}[7/7] 健康检查...${NC}"
if curl -f http://localhost:${PORT:-8080}/healthz > /dev/null 2>&1; then
    echo -e "${GREEN}✓ 服务健康检查通过${NC}"
    echo -e "${GREEN}  URL: http://localhost:${PORT:-8080}/healthz${NC}"
else
    echo -e "${YELLOW}⚠ 服务健康检查失败或服务未启动${NC}"
    echo -e "  提示: 如果服务未启动，运行 docker-compose up -d"
fi
echo ""

# 总结
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  验证总结${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✓ 所有检查通过！配置正常${NC}"
    echo ""
    echo "你可以运行以下命令："
    echo "  启动服务: docker-compose up -d"
    echo "  查看日志: docker-compose logs -f"
    echo "  查看状态: docker-compose ps"
    EXIT_CODE=0
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}⚠ 有 $WARNINGS 个警告${NC}"
    echo "  建议查看上述警告信息"
    echo ""
    echo "如果需要修复，运行："
    echo -e "  ${BLUE}./quick-fix.sh${NC}"
    EXIT_CODE=0
else
    echo -e "${RED}✗ 发现 $ERRORS 个错误和 $WARNINGS 个警告${NC}"
    echo ""
    echo "修复建议："
    echo -e "  1. 运行快速修复脚本: ${BLUE}./quick-fix.sh${NC}"
    echo -e "  2. 查看详细文档: ${BLUE}cat FIX_README.md${NC}"
    echo -e "  3. 查看故障排除: ${BLUE}cat TROUBLESHOOTING.md${NC}"
    EXIT_CODE=1
fi

echo ""
exit $EXIT_CODE

