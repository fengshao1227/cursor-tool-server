.PHONY: help deploy start stop restart logs status backup restore health clean auto-deploy auto-deploy-force auto-deploy-rollback setup-cron remove-cron

# 默认目标
help:
	@echo "License Server 管理命令"
	@echo ""
	@echo "使用方法: make [target]"
	@echo ""
	@echo "可用命令:"
	@echo "  deploy            - 一键部署（首次部署）"
	@echo "  start             - 启动服务"
	@echo "  stop              - 停止服务"
	@echo "  restart           - 重启服务"
	@echo "  logs              - 查看实时日志"
	@echo "  status            - 查看服务状态"
	@echo "  backup            - 备份数据库"
	@echo "  restore           - 恢复数据库"
	@echo "  health            - 健康检查"
	@echo "  clean             - 清理容器和数据卷（危险！）"
	@echo ""
	@echo "自动部署命令:"
	@echo "  auto-deploy       - 自动部署（检查更新并部署）"
	@echo "  auto-deploy-force - 强制自动部署（即使没有更新）"
	@echo "  auto-deploy-rollback - 回滚到上一个版本"
	@echo "  setup-cron        - 设置定时自动部署"
	@echo "  remove-cron       - 移除定时自动部署"
	@echo ""

# 检测 docker-compose 命令
DOCKER_COMPOSE := $(shell which docker-compose 2>/dev/null || echo "docker compose")

# 一键部署
deploy:
	@./deploy.sh

# 启动服务
start:
	@echo "启动服务..."
	@$(DOCKER_COMPOSE) up -d
	@echo "服务已启动！"
	@$(DOCKER_COMPOSE) ps

# 停止服务
stop:
	@echo "停止服务..."
	@$(DOCKER_COMPOSE) down
	@echo "服务已停止！"

# 重启服务
restart:
	@echo "重启服务..."
	@$(DOCKER_COMPOSE) restart
	@echo "服务已重启！"
	@$(DOCKER_COMPOSE) ps

# 查看日志
logs:
	@$(DOCKER_COMPOSE) logs -f

# 查看服务状态
status:
	@$(DOCKER_COMPOSE) ps

# 备份数据库
backup:
	@./backup.sh

# 恢复数据库
restore:
	@./restore.sh

# 健康检查
health:
	@./health-check.sh

# 清理（危险操作）
clean:
	@echo "警告: 此操作将删除所有容器和数据卷！"
	@read -p "确认继续？(yes/no) " confirm; \
	if [ "$$confirm" = "yes" ]; then \
		$(DOCKER_COMPOSE) down -v; \
		echo "清理完成！"; \
	else \
		echo "已取消"; \
	fi

# 初始化环境变量
init:
	@if [ ! -f .env ]; then \
		cp env.example .env; \
		echo "已创建 .env 文件，请编辑配置后再部署"; \
	else \
		echo ".env 文件已存在"; \
	fi

# 构建镜像（无缓存）
build:
	@echo "构建 Docker 镜像..."
	@$(DOCKER_COMPOSE) build --no-cache

# 查看容器资源使用
stats:
	@docker stats --no-stream

# 进入 MySQL 容器
mysql:
	@$(DOCKER_COMPOSE) exec mysql mysql -uroot -p

# 进入 License Server 容器
shell:
	@$(DOCKER_COMPOSE) exec license-server sh

# 查看最近50行日志
tail:
	@$(DOCKER_COMPOSE) logs --tail=50

# 安装依赖（开发模式）
install:
	@npm install
	@cd admin && npm install

# 开发模式运行
dev:
	@npm run dev

# 测试健康端点
test-health:
	@curl -f http://localhost:8080/healthz && echo " - OK" || echo " - FAILED"

# 自动部署（检查更新并部署）
auto-deploy:
	@./auto-deploy.sh

# 强制自动部署（即使没有更新）
auto-deploy-force:
	@./auto-deploy.sh --force

# 回滚到上一个版本
auto-deploy-rollback:
	@./auto-deploy.sh --rollback

# 设置定时自动部署
setup-cron:
	@./setup-auto-deploy.sh

# 移除定时自动部署
remove-cron:
	@./setup-auto-deploy.sh --remove

