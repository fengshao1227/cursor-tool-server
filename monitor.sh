#!/bin/bash

# License Server 监控和自动恢复脚本
# 使用方法: ./monitor.sh
# 建议配置 crontab: */5 * * * * /path/to/monitor.sh

set -e

# 配置
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LOG_FILE="${SCRIPT_DIR}/monitor.log"
MAX_LOG_SIZE=10485760  # 10MB

# 获取配置
cd "$SCRIPT_DIR"
if [ -f .env ]; then
    source .env
fi
PORT=${PORT:-8080}

# 使用 docker compose 或 docker-compose
DOCKER_COMPOSE="docker compose"
if ! docker compose version &> /dev/null; then
    DOCKER_COMPOSE="docker-compose"
fi

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# 清理大日志文件
if [ -f "$LOG_FILE" ] && [ $(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null) -gt $MAX_LOG_SIZE ]; then
    mv "$LOG_FILE" "${LOG_FILE}.old"
    log "日志文件已轮转"
fi

# 发送告警（可根据需要配置）
send_alert() {
    local message="$1"
    log "告警: $message"
    
    # 可以在这里集成告警通知服务
    # 例如: curl -X POST https://your-webhook-url -d "{\"text\":\"$message\"}"
    
    # 或发送邮件
    # echo "$message" | mail -s "License Server Alert" admin@example.com
}

# 检查健康状态
check_health() {
    if curl -f -s -o /dev/null -w "%{http_code}" http://localhost:${PORT}/healthz | grep -q "200"; then
        return 0
    else
        return 1
    fi
}

# 检查容器状态
check_container() {
    local container="$1"
    if $DOCKER_COMPOSE ps | grep "$container" | grep -q "Up"; then
        return 0
    else
        return 1
    fi
}

# 重启服务
restart_service() {
    log "尝试重启服务..."
    $DOCKER_COMPOSE restart
    sleep 10
    
    if check_health; then
        log "服务重启成功"
        send_alert "License Server 已自动重启并恢复正常"
        return 0
    else
        log "服务重启失败"
        send_alert "License Server 重启失败，需要人工介入！"
        return 1
    fi
}

# 主监控逻辑
main() {
    log "开始健康检查..."
    
    # 检查 MySQL 容器
    if ! check_container "mysql"; then
        log "MySQL 容器未运行"
        send_alert "MySQL 容器未运行"
        restart_service
        return
    fi
    
    # 检查 License Server 容器
    if ! check_container "license-server"; then
        log "License Server 容器未运行"
        send_alert "License Server 容器未运行"
        restart_service
        return
    fi
    
    # 检查健康端点
    if ! check_health; then
        log "健康检查失败"
        send_alert "License Server 健康检查失败"
        
        # 尝试重启
        restart_service
        return
    fi
    
    # 检查磁盘空间
    DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
    if [ "$DISK_USAGE" -gt 90 ]; then
        log "警告: 磁盘使用率过高 ${DISK_USAGE}%"
        send_alert "License Server 磁盘使用率过高: ${DISK_USAGE}%"
    fi
    
    # 检查内存使用
    if command -v free &> /dev/null; then
        MEM_USAGE=$(free | grep Mem | awk '{printf("%.0f", $3/$2 * 100)}')
        if [ "$MEM_USAGE" -gt 90 ]; then
            log "警告: 内存使用率过高 ${MEM_USAGE}%"
            send_alert "License Server 内存使用率过高: ${MEM_USAGE}%"
        fi
    fi
    
    log "健康检查完成 - 状态正常"
}

# 执行监控
main

# 如果日志文件太大，只保留最后1000行
if [ -f "$LOG_FILE" ]; then
    tail -n 1000 "$LOG_FILE" > "${LOG_FILE}.tmp"
    mv "${LOG_FILE}.tmp" "$LOG_FILE"
fi

