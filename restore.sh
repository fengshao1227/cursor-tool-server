#!/bin/bash

# License Server 数据库恢复脚本
# 使用方法: ./restore.sh <backup_file>

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 检查参数
if [ $# -eq 0 ]; then
    echo -e "${RED}错误: 请指定备份文件${NC}"
    echo "使用方法: $0 <backup_file>"
    echo ""
    echo "可用的备份文件:"
    ls -lh ./backups/license_db_*.sql.gz 2>/dev/null || echo "  无备份文件"
    exit 1
fi

BACKUP_FILE="$1"

# 检查备份文件是否存在
if [ ! -f "$BACKUP_FILE" ]; then
    echo -e "${RED}错误: 备份文件不存在: $BACKUP_FILE${NC}"
    exit 1
fi

# 获取脚本所在目录
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# 检查 .env 文件
if [ ! -f .env ]; then
    echo -e "${RED}错误: .env 文件不存在${NC}"
    exit 1
fi

# 加载环境变量
source .env

echo -e "${YELLOW}警告: 此操作将覆盖当前数据库！${NC}"
echo "备份文件: $BACKUP_FILE"
echo ""
read -p "确认继续？(yes/no) " -r
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "已取消"
    exit 0
fi

echo ""
echo "开始恢复数据库..."

# 解压备份文件（如果是 .gz）
if [[ "$BACKUP_FILE" == *.gz ]]; then
    echo "正在解压备份文件..."
    TEMP_FILE="/tmp/license_db_restore_$$.sql"
    gunzip -c "$BACKUP_FILE" > "$TEMP_FILE"
    RESTORE_FILE="$TEMP_FILE"
else
    RESTORE_FILE="$BACKUP_FILE"
fi

# 执行恢复
echo "正在恢复数据..."
docker-compose exec -T mysql mysql \
    -uroot \
    -p"${MYSQL_ROOT_PASSWORD}" \
    "${MYSQL_DATABASE}" \
    < "$RESTORE_FILE"

# 清理临时文件
if [ -n "$TEMP_FILE" ] && [ -f "$TEMP_FILE" ]; then
    rm "$TEMP_FILE"
fi

echo -e "${GREEN}✓ 恢复完成！${NC}"
echo ""
echo "重启服务以应用更改..."
docker-compose restart license-server

echo -e "${GREEN}✓ 数据库恢复成功！${NC}"

