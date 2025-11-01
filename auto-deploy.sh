#!/bin/bash

# License Server 自动更新和部署脚本
# 功能：
#   - 自动从 Git 拉取最新代码
#   - 自动备份数据库
#   - 自动构建和部署
#   - 健康检查和回滚机制
#   - 日志记录
# 使用方法: ./auto-deploy.sh [选项]
#   选项:
#     --no-backup     跳过备份
#     --no-pull       跳过 Git 拉取
#     --force         强制部署（即使没有更新）
#     --rollback      回滚到上一个版本
#     --cron          静默模式（用于 cron）

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

LOG_DIR="${LOG_DIR:-./logs}"
BACKUP_DIR="${BACKUP_DIR:-./backups}"
LOG_FILE="${LOG_FILE:-$LOG_DIR/auto-deploy.log}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
CURRENT_VERSION_FILE="$SCRIPT_DIR/.current_version"
PREVIOUS_VERSION_FILE="$SCRIPT_DIR/.previous_version"

# 创建日志目录
mkdir -p "$LOG_DIR"

# 日志函数
log() {
    local level=$1
    shift
    local message="$@"
    local log_entry="[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message"
    
    # 输出到控制台（带颜色）
    case $level in
        INFO)
            echo -e "${GREEN}$log_entry${NC}"
            ;;
        WARN)
            echo -e "${YELLOW}$log_entry${NC}"
            ;;
        ERROR)
            echo -e "${RED}$log_entry${NC}"
            ;;
        DEBUG)
            echo -e "${BLUE}$log_entry${NC}"
            ;;
        *)
            echo "$log_entry"
            ;;
    esac
    
    # 写入日志文件
    echo "$log_entry" >> "$LOG_FILE"
}

# 错误处理
error_exit() {
    log ERROR "$@"
    exit 1
}

# 解析命令行参数
NO_BACKUP=false
NO_PULL=false
FORCE=false
ROLLBACK=false
CRON_MODE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --no-backup)
            NO_BACKUP=true
            shift
            ;;
        --no-pull)
            NO_PULL=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --rollback)
            ROLLBACK=true
            shift
            ;;
        --cron)
            CRON_MODE=true
            shift
            ;;
        *)
            log ERROR "未知参数: $1"
            exit 1
            ;;
    esac
done

# 检测 Docker Compose
detect_docker_compose() {
    if docker compose version &> /dev/null; then
        echo "docker compose"
    elif command -v docker-compose &> /dev/null; then
        echo "docker-compose"
    else
        error_exit "Docker Compose 未安装"
    fi
}

DOCKER_COMPOSE=$(detect_docker_compose)

# 获取当前版本（Git commit hash）
get_current_version() {
    if [ -d .git ]; then
        git rev-parse HEAD 2>/dev/null || echo "unknown"
    else
        echo "unknown"
    fi
}

# 检查是否有更新
check_for_updates() {
    if [ "$NO_PULL" = true ] || [ ! -d .git ]; then
        return 1
    fi
    
    log INFO "检查 Git 更新..."
    
    # 获取远程更新
    git fetch origin 2>/dev/null || return 1
    
    local current_branch=$(git rev-parse --abbrev-ref HEAD)
    local local_commit=$(git rev-parse HEAD)
    local remote_commit=$(git rev-parse origin/$current_branch 2>/dev/null || echo "")
    
    if [ -z "$remote_commit" ]; then
        log WARN "无法获取远程分支信息"
        return 1
    fi
    
    if [ "$local_commit" != "$remote_commit" ]; then
        log INFO "发现新版本: $local_commit -> $remote_commit"
        return 0
    else
        log INFO "已是最新版本"
        return 1
    fi
}

# 备份数据库
backup_database() {
    if [ "$NO_BACKUP" = true ]; then
        log WARN "跳过备份（--no-backup）"
        return 0
    fi
    
    log INFO "备份数据库..."
    
    if [ -f backup.sh ]; then
        if [ "$CRON_MODE" = true ]; then
            ./backup.sh >> "$LOG_FILE" 2>&1
        else
            ./backup.sh
        fi
        log INFO "数据库备份完成"
    else
        log WARN "backup.sh 不存在，跳过备份"
    fi
}

# 拉取最新代码
pull_latest_code() {
    if [ "$NO_PULL" = true ]; then
        log WARN "跳过 Git 拉取（--no-pull）"
        return 0
    fi
    
    if [ ! -d .git ]; then
        log WARN "非 Git 仓库，跳过拉取"
        return 0
    fi
    
    log INFO "拉取最新代码..."
    
    # 保存当前版本
    local current_version=$(get_current_version)
    echo "$current_version" > "$PREVIOUS_VERSION_FILE"
    
    # 检查未提交的更改
    if [[ -n $(git status -s) ]]; then
        log WARN "检测到未提交的更改"
        if [ "$CRON_MODE" = false ]; then
            git status -s
            read -p "是否暂存更改并继续？(y/n) " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                error_exit "已取消更新"
            fi
        fi
        git stash push -m "Auto-stash before deploy $TIMESTAMP"
    fi
    
    # 拉取最新代码
    git pull origin $(git rev-parse --abbrev-ref HEAD) || error_exit "Git 拉取失败"
    
    local new_version=$(get_current_version)
    echo "$new_version" > "$CURRENT_VERSION_FILE"
    
    log INFO "代码更新完成: $current_version -> $new_version"
}

# 停止服务
stop_services() {
    log INFO "停止服务..."
    $DOCKER_COMPOSE down 2>/dev/null || true
    log INFO "服务已停止"
}

# 构建镜像
build_image() {
    log INFO "构建 Docker 镜像..."
    if [ "$CRON_MODE" = true ]; then
        $DOCKER_COMPOSE build --no-cache >> "$LOG_FILE" 2>&1
    else
        $DOCKER_COMPOSE build --no-cache
    fi
    
    if [ $? -eq 0 ]; then
        log INFO "镜像构建成功"
    else
        error_exit "镜像构建失败"
    fi
}

# 启动服务
start_services() {
    log INFO "启动服务..."
    if [ "$CRON_MODE" = true ]; then
        $DOCKER_COMPOSE up -d >> "$LOG_FILE" 2>&1
    else
        $DOCKER_COMPOSE up -d
    fi
    
    if [ $? -eq 0 ]; then
        log INFO "服务已启动"
    else
        error_exit "服务启动失败"
    fi
}

# 健康检查
health_check() {
    log INFO "执行健康检查..."
    
    # 从 .env 读取端口
    local port=$(grep "^PORT=" .env 2>/dev/null | cut -d '=' -f2 || echo "8080")
    port=${port:-8080}
    
    local max_retries=30
    local retry_count=0
    local health_url="http://localhost:${port}/healthz"
    
    while [ $retry_count -lt $max_retries ]; do
        if curl -f -s "$health_url" > /dev/null 2>&1; then
            log INFO "✓ 健康检查通过"
            return 0
        fi
        
        retry_count=$((retry_count + 1))
        if [ "$CRON_MODE" = false ]; then
            echo "等待服务启动... ($retry_count/$max_retries)"
        fi
        sleep 2
    done
    
    log ERROR "✗ 健康检查失败"
    return 1
}

# 回滚
rollback() {
    log INFO "开始回滚..."
    
    if [ ! -f "$PREVIOUS_VERSION_FILE" ]; then
        error_exit "未找到上一个版本信息，无法回滚"
    fi
    
    local previous_version=$(cat "$PREVIOUS_VERSION_FILE")
    
    if [ ! -d .git ]; then
        error_exit "非 Git 仓库，无法回滚"
    fi
    
    log INFO "回滚到版本: $previous_version"
    
    # 停止服务
    stop_services
    
    # 检出上一个版本
    git checkout "$previous_version" || error_exit "Git checkout 失败"
    
    # 重新构建和启动
    build_image
    start_services
    
    # 健康检查
    if health_check; then
        log INFO "回滚成功"
        # 更新版本文件
        echo "$previous_version" > "$CURRENT_VERSION_FILE"
    else
        error_exit "回滚后健康检查失败"
    fi
}

# 主部署流程
main_deploy() {
    log INFO "=========================================="
    log INFO "开始自动部署流程"
    log INFO "=========================================="
    
    # 如果是回滚模式
    if [ "$ROLLBACK" = true ]; then
        rollback
        return 0
    fi
    
    # 检查更新
    if [ "$FORCE" != true ]; then
        if ! check_for_updates; then
            log INFO "没有更新，退出"
            return 0
        fi
    fi
    
    # 备份数据库
    backup_database
    
    # 拉取最新代码
    pull_latest_code
    
    # 停止服务
    stop_services
    
    # 构建镜像
    build_image
    
    # 启动服务
    start_services
    
    # 等待服务启动
    log INFO "等待服务启动..."
    sleep 5
    
    # 健康检查
    if health_check; then
        log INFO "=========================================="
        log INFO "部署成功！"
        log INFO "=========================================="
        
        # 显示服务信息
        if [ "$CRON_MODE" = false ]; then
            local port=$(grep "^PORT=" .env 2>/dev/null | cut -d '=' -f2 || echo "8080")
            port=${port:-8080}
            echo ""
            echo "服务信息:"
            echo "  - API 地址: http://localhost:${port}"
            echo "  - 管理后台: http://localhost:${port}/admin"
            echo "  - 健康检查: http://localhost:${port}/healthz"
            echo ""
            echo "查看日志: $DOCKER_COMPOSE logs -f"
        fi
        
        return 0
    else
        log ERROR "部署失败，尝试回滚..."
        
        # 尝试回滚
        if rollback; then
            log INFO "已回滚到上一个版本"
        else
            log ERROR "回滚失败，请手动检查"
        fi
        
        error_exit "部署失败"
    fi
}

# 执行主流程
main_deploy

