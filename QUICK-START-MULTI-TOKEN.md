# 🚀 多Token功能快速启动指南

## 一键部署步骤

### 1️⃣ 运行数据库迁移（必须）

```bash
# 方式1: 使用 MySQL 命令行
mysql -u root -p license_db < migration-multi-token.sql

# 方式2: 登录 MySQL 后执行
mysql -u root -p
USE license_db;
source migration-multi-token.sql;
```

### 2️⃣ 重启应用

```bash
# 如果是开发环境
npm run dev

# 如果是生产环境（Docker）
docker-compose restart

# 如果是生产环境（systemd）
sudo systemctl restart license-server
```

### 3️⃣ 使用新功能

#### ✅ 功能1：添加Token后保持独占模式

1. 登录管理后台
2. 进入"🔑 Token管理"
3. 添加Token时勾选"🔒 独占模式"
4. 点击"添加Token"
5. ✨ 复选框保持勾选，可以继续添加

#### ✅ 功能2：一个卡密绑定多个Token

1. 进入"🎫 卡密管理"
2. 点击"🔽 展开 手动选择Token（可选多个）"
3. 勾选需要的Token（支持多选）
4. 设置数量：**生成1个卡密**
5. 点击"生成卡密"
6. ✨ 这个卡密会包含所有选择的Token

#### 示例：一卡三号

```
1. 添加3个独占Token
2. 生成卡密时选择这3个Token
3. 生成1个卡密
4. 客户端激活后收到：
   {
     "cursorTokens": [
       "token1...",
       "token2...",
       "token3..."
     ]
   }
```

## 验证功能是否正常

### 测试1：检查数据库表

```sql
-- 查看关联表是否创建成功
DESC license_tokens;

-- 查看现有数据是否迁移
SELECT COUNT(*) FROM license_tokens;
```

### 测试2：生成测试卡密

1. 添加2个独占Token
2. 手动选择这2个Token
3. 生成1个卡密
4. 查看数据库：

```sql
-- 查看卡密关联的Token数量（应该是2）
SELECT 
  l.license_key,
  COUNT(lt.cursor_token_id) as token_count
FROM licenses l
LEFT JOIN license_tokens lt ON l.id = lt.license_id
GROUP BY l.id;
```

### 测试3：激活卡密

使用API工具（如Postman）测试：

```bash
curl -X POST http://localhost:3000/v1/licenses/activate \
  -H "Content-Type: application/json" \
  -d '{
    "licenseKey": "YOUR-LICENSE-KEY",
    "machineId": "test-machine-001"
  }'
```

响应应该包含：
```json
{
  "success": true,
  "data": {
    "cursorTokens": ["token1", "token2"]
  }
}
```

## 常见问题

### ❓ 迁移后旧卡密还能用吗？

✅ **可以**。迁移脚本会自动将现有的卡密-Token关系导入到新表中。

### ❓ 客户端需要升级吗？

⚠️ **不强制**，但推荐升级：
- 旧客户端：仍然可以使用 `cursorToken` 字段（返回第一个Token）
- 新客户端：使用 `cursorTokens` 字段获取所有Token

### ❓ 独占Token被消耗后能恢复吗？

❌ **不能**。独占Token一旦被使用，就会标记为"已消耗"。如果需要重新使用，需要：
1. 删除使用该Token的卡密
2. Token会自动恢复为可用状态

### ❓ 可以给一个卡密绑定10个Token吗？

✅ **可以**。理论上没有上限，但建议：
- 独占卡密：3-5个Token
- 普通卡密：1-3个Token

## 回滚方案（如果遇到问题）

如果新功能有问题，可以临时回滚：

```sql
-- 备份新表
CREATE TABLE license_tokens_backup AS SELECT * FROM license_tokens;

-- 删除新表
DROP TABLE license_tokens;

-- 恢复旧代码
git checkout HEAD~1

-- 重启服务
sudo systemctl restart license-server
```

## 性能优化建议

如果有大量卡密和Token，建议优化查询：

```sql
-- 为高频查询添加索引（迁移脚本已包含）
CREATE INDEX idx_license_id ON license_tokens(license_id);
CREATE INDEX idx_token_id ON license_tokens(cursor_token_id);
```

## 监控指标

新功能上线后，可以监控：

```sql
-- 多Token卡密统计
SELECT 
  COUNT(DISTINCT l.id) as total_licenses,
  AVG(token_count) as avg_tokens_per_license,
  MAX(token_count) as max_tokens_per_license
FROM licenses l
LEFT JOIN (
  SELECT license_id, COUNT(*) as token_count
  FROM license_tokens
  GROUP BY license_id
) lt ON l.id = lt.license_id;
```

## 需要帮助？

如果遇到问题，请检查：

1. ✅ 数据库迁移是否成功执行
2. ✅ 服务是否重启
3. ✅ 浏览器缓存是否清除（Ctrl+F5）
4. ✅ API响应是否包含 `cursorTokens` 字段

详细文档请查看：`MULTI-TOKEN-FEATURE.md`

