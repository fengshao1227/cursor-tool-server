#!/bin/bash

# License Server 定时自动部署设置脚本
# 功能：设置 cron 定时任务，自动执行部署脚本
# 使用方法: ./setup-auto-deploy.sh [选项]
#   选项:
#     --daily     每天执行（默认凌晨2点）
#     --hourly    每小时执行
#     --weekly    每周执行（默认周一凌晨2点）
#     --time TIME 指定执行时间（格式: HH:MM，仅用于 --daily）
#     --remove    移除定时任务

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
DEPLOY_SCRIPT="$SCRIPT_DIR/auto-deploy.sh"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 检查脚本是否存在
if [ ! -f "$DEPLOY_SCRIPT" ]; then
    echo -e "${RED}错误: auto-deploy.sh 不存在${NC}"
    exit 1
fi

# 获取 cron 任务标识
CRON_COMMENT="# License Server Auto Deploy"

# 显示当前定时任务
show_current_cron() {
    echo -e "${YELLOW}当前定时任务:${NC}"
    crontab -l 2>/dev/null | grep "$CRON_COMMENT" || echo "无"
    echo ""
}

# 移除定时任务
remove_cron() {
    echo "移除定时任务..."
    crontab -l 2>/dev/null | grep -v "$CRON_COMMENT" | crontab -
    echo -e "${GREEN}✓ 定时任务已移除${NC}"
}

# 添加定时任务
add_cron() {
    local schedule=$1
    local cron_line="$schedule $CRON_COMMENT $DEPLOY_SCRIPT --cron >> $SCRIPT_DIR/logs/cron.log 2>&1"
    
    # 移除旧任务（如果存在）
    remove_cron
    
    # 添加新任务
    (crontab -l 2>/dev/null; echo "$cron_line") | crontab -
    echo -e "${GREEN}✓ 定时任务已添加${NC}"
    echo ""
    echo "定时任务详情:"
    echo "  执行时间: $schedule"
    echo "  执行脚本: $DEPLOY_SCRIPT"
    echo "  日志文件: $SCRIPT_DIR/logs/cron.log"
}

# 解析参数
SCHEDULE=""
REMOVE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --daily)
            SCHEDULE="0 2 * * *"
            shift
            ;;
        --hourly)
            SCHEDULE="0 * * * *"
            shift
            ;;
        --weekly)
            SCHEDULE="0 2 * * 1"
            shift
            ;;
        --time)
            if [ -z "$2" ]; then
                echo -e "${RED}错误: --time 需要指定时间（格式: HH:MM）${NC}"
                exit 1
            fi
            local time_str=$2
            local hour=$(echo $time_str | cut -d: -f1)
            local minute=$(echo $time_str | cut -d: -f2)
            SCHEDULE="$minute $hour * * *"
            shift 2
            ;;
        --remove)
            REMOVE=true
            shift
            ;;
        *)
            echo -e "${RED}未知参数: $1${NC}"
            exit 1
            ;;
    esac
done

# 显示当前任务
show_current_cron

# 如果指定移除
if [ "$REMOVE" = true ]; then
    remove_cron
    exit 0
fi

# 如果没有指定时间表，提示用户选择
if [ -z "$SCHEDULE" ]; then
    echo "请选择定时任务类型:"
    echo "  1) 每天执行（默认凌晨2点）"
    echo "  2) 每小时执行"
    echo "  3) 每周执行（周一凌晨2点）"
    echo "  4) 自定义时间"
    echo "  5) 移除定时任务"
    echo ""
    read -p "请选择 (1-5): " choice
    
    case $choice in
        1)
            SCHEDULE="0 2 * * *"
            ;;
        2)
            SCHEDULE="0 * * * *"
            ;;
        3)
            SCHEDULE="0 2 * * 1"
            ;;
        4)
            read -p "请输入执行时间（格式: HH:MM，如 02:00）: " time_str
            local hour=$(echo $time_str | cut -d: -f1)
            local minute=$(echo $time_str | cut -d: -f2)
            SCHEDULE="$minute $hour * * *"
            ;;
        5)
            remove_cron
            exit 0
            ;;
        *)
            echo -e "${RED}无效选择${NC}"
            exit 1
            ;;
    esac
fi

# 添加定时任务
add_cron "$SCHEDULE"

echo ""
echo -e "${GREEN}设置完成！${NC}"
echo ""
echo "查看定时任务: crontab -l"
echo "编辑定时任务: crontab -e"
echo "查看执行日志: tail -f $SCRIPT_DIR/logs/cron.log"

