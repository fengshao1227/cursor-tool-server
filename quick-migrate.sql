-- 快速迁移脚本：添加独占Token功能字段
-- 使用方法：mysql -u root -p license_db < quick-migrate.sql

USE license_db;

-- 添加字段（如果已存在会忽略）
ALTER TABLE cursor_tokens 
ADD COLUMN IF NOT EXISTS is_exclusive BOOLEAN NOT NULL DEFAULT FALSE COMMENT '是否独占（一个Token只能生成一个卡密）',
ADD COLUMN IF NOT EXISTS is_consumed BOOLEAN NOT NULL DEFAULT FALSE COMMENT '是否已消耗（独占Token生成卡密后标记为已消耗）';

-- 添加索引
ALTER TABLE cursor_tokens 
ADD INDEX IF NOT EXISTS idx_exclusive_consumed (is_exclusive, is_consumed, status);

-- 验证字段是否添加成功
DESCRIBE cursor_tokens;

-- 查看当前token状态
SELECT 
    COUNT(*) as total_tokens,
    SUM(CASE WHEN is_exclusive = TRUE THEN 1 ELSE 0 END) as exclusive_tokens,
    SUM(CASE WHEN is_exclusive = TRUE AND is_consumed = FALSE THEN 1 ELSE 0 END) as available_exclusive_tokens
FROM cursor_tokens;

SELECT '✅ 迁移完成！' as status;

