-- 卡密多Token支持迁移脚本
-- 用途：支持一个卡密关联多个Cursor Token

USE license_db;

-- ============================================
-- 1. 创建卡密-Token关联表
-- ============================================
CREATE TABLE IF NOT EXISTS license_tokens (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  
  license_id BIGINT NOT NULL COMMENT '卡密ID',
  cursor_token_id BIGINT NOT NULL COMMENT 'Cursor Token ID',
  
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  
  UNIQUE KEY uniq_license_token (license_id, cursor_token_id),
  INDEX idx_license_id (license_id),
  INDEX idx_token_id (cursor_token_id),
  
  CONSTRAINT fk_license_tokens_license 
    FOREIGN KEY (license_id) REFERENCES licenses(id) ON DELETE CASCADE,
  CONSTRAINT fk_license_tokens_token 
    FOREIGN KEY (cursor_token_id) REFERENCES cursor_tokens(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='卡密-Token关联表（多对多）';

-- ============================================
-- 2. 迁移现有数据到关联表
-- ============================================
-- 将现有的 licenses.cursor_token_id 数据迁移到 license_tokens 表
INSERT INTO license_tokens (license_id, cursor_token_id)
SELECT id, cursor_token_id
FROM licenses
WHERE cursor_token_id IS NOT NULL
ON DUPLICATE KEY UPDATE license_id = license_id; -- 避免重复插入

-- ============================================
-- 3. 添加索引优化查询
-- ============================================
-- licenses表保留cursor_token_id字段，但不再使用（为了兼容性）
-- 如果需要删除该字段，取消下面注释：
-- ALTER TABLE licenses DROP COLUMN cursor_token_id;

SELECT '✅ Migration completed: Multi-token support added' AS status;

