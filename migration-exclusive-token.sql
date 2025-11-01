-- 添加独占Token功能的数据库迁移脚本
-- 执行前请先备份数据库

USE license_db;

-- 1. 为 cursor_tokens 表添加独占功能字段
ALTER TABLE cursor_tokens 
ADD COLUMN IF NOT EXISTS is_exclusive BOOLEAN NOT NULL DEFAULT FALSE COMMENT '是否独占（一个Token只能生成一个卡密）',
ADD COLUMN IF NOT EXISTS is_consumed BOOLEAN NOT NULL DEFAULT FALSE COMMENT '是否已消耗（独占Token生成卡密后标记为已消耗）';

-- 2. 添加索引以提升查询性能
ALTER TABLE cursor_tokens 
ADD INDEX IF NOT EXISTS idx_exclusive_consumed (is_exclusive, is_consumed, status);

-- 3. 查看当前token状态
SELECT 
    COUNT(*) as total_tokens,
    SUM(CASE WHEN is_exclusive = TRUE THEN 1 ELSE 0 END) as exclusive_tokens,
    SUM(CASE WHEN is_exclusive = TRUE AND is_consumed = FALSE THEN 1 ELSE 0 END) as available_exclusive_tokens,
    SUM(CASE WHEN is_exclusive = FALSE THEN 1 ELSE 0 END) as normal_tokens
FROM cursor_tokens;

-- 4. （可选）将现有token标记为非独占
-- UPDATE cursor_tokens SET is_exclusive = FALSE, is_consumed = FALSE WHERE is_exclusive IS NULL;

-- 迁移完成提示
SELECT '✅ 迁移完成！现在可以使用独占Token功能了' as status;

