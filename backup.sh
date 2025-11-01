#!/bin/bash

# License Server 数据库备份脚本
# 使用方法: ./backup.sh

set -e

# 颜色输出
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 配置
BACKUP_DIR="${BACKUP_DIR:-./backups}"
KEEP_DAYS="${KEEP_DAYS:-7}"

# 创建备份目录
mkdir -p "$BACKUP_DIR"

# 获取脚本所在目录
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# 检查 .env 文件
if [ ! -f .env ]; then
    echo -e "${YELLOW}警告: .env 文件不存在${NC}"
    exit 1
fi

# 加载环境变量
source .env

# 生成时间戳
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/license_db_${TIMESTAMP}.sql"

echo "开始备份数据库..."
echo "备份文件: $BACKUP_FILE"

# 执行备份
docker-compose exec -T mysql mysqldump \
    -uroot \
    -p"${MYSQL_ROOT_PASSWORD}" \
    "${MYSQL_DATABASE}" \
    --single-transaction \
    --quick \
    --lock-tables=false \
    > "$BACKUP_FILE"

# 压缩备份文件
gzip "$BACKUP_FILE"
BACKUP_FILE="${BACKUP_FILE}.gz"

echo -e "${GREEN}✓ 备份完成: $BACKUP_FILE${NC}"

# 显示备份文件大小
du -h "$BACKUP_FILE"

# 清理旧备份
if [ "$KEEP_DAYS" -gt 0 ]; then
    echo ""
    echo "清理 ${KEEP_DAYS} 天前的备份..."
    find "$BACKUP_DIR" -name "license_db_*.sql.gz" -mtime +$KEEP_DAYS -delete
    echo -e "${GREEN}✓ 清理完成${NC}"
fi

# 显示所有备份
echo ""
echo "当前所有备份:"
ls -lh "$BACKUP_DIR"/license_db_*.sql.gz 2>/dev/null || echo "无备份文件"

echo ""
echo "备份完成！"

