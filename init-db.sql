-- License Server 数据库初始化脚本
-- 用途：Cursor 软件卡密系统

CREATE DATABASE IF NOT EXISTS license_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE license_db;

-- ============================================
-- 1. 卡密表（核心表）
-- ============================================
CREATE TABLE IF NOT EXISTS licenses (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  
  -- 卡密信息
  license_key VARCHAR(64) NOT NULL UNIQUE COMMENT '卡密（唯一）',
  
  -- Cursor 相关
  cursor_token_id BIGINT COMMENT '关联的 Cursor Token ID',
  cursor_email VARCHAR(128) NOT NULL COMMENT '自动生成的随机邮箱',
  
  -- 有效期
  valid_days INT NOT NULL COMMENT '有效天数（从激活时算起）',
  activated_at DATETIME COMMENT '激活时间',
  expires_at DATETIME COMMENT '过期时间',
  
  -- 状态
  status ENUM('pending','active','expired','revoked') NOT NULL DEFAULT 'pending' COMMENT 'pending=未激活, active=激活中, expired=已过期, revoked=已禁用',
  
  -- 设备限制
  max_devices INT NOT NULL DEFAULT 1 COMMENT '最大设备数',
  
  -- 元信息
  note VARCHAR(255) COMMENT '备注',
  created_by VARCHAR(64) COMMENT '创建者',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  last_verified_at DATETIME COMMENT '最后验证时间',
  
  INDEX idx_license_key (license_key),
  INDEX idx_status (status),
  INDEX idx_expires_at (expires_at),
  INDEX idx_created_at (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='卡密表';

-- ============================================
-- 2. Cursor Token 池
-- ============================================
CREATE TABLE IF NOT EXISTS cursor_tokens (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  
  -- Token 信息（加密存储）
  token_encrypted TEXT NOT NULL COMMENT 'Cursor Token（AES-256 加密）',
  token_iv VARCHAR(64) NOT NULL COMMENT '加密初始化向量',
  
  -- 状态
  status ENUM('available','in_use','exhausted','disabled') NOT NULL DEFAULT 'available' COMMENT '状态',
  
  -- 使用统计
  assigned_count INT NOT NULL DEFAULT 0 COMMENT '已分配次数',
  max_assignments INT DEFAULT NULL COMMENT '最大分配次数（NULL=无限制）',
  
  -- 独占功能
  is_exclusive BOOLEAN NOT NULL DEFAULT FALSE COMMENT '是否独占（一个Token只能生成一个卡密）',
  is_consumed BOOLEAN NOT NULL DEFAULT FALSE COMMENT '是否已消耗（独占Token生成卡密后标记为已消耗）',
  
  -- 元信息
  note VARCHAR(255) COMMENT '备注',
  added_by VARCHAR(64) COMMENT '添加者',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_used_at DATETIME COMMENT '最后使用时间',
  
  INDEX idx_status (status),
  INDEX idx_exclusive_consumed (is_exclusive, is_consumed, status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Cursor Token 池';

-- ============================================
-- 3. 设备激活记录
-- ============================================
CREATE TABLE IF NOT EXISTS activations (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  
  license_id BIGINT NOT NULL,
  machine_id VARCHAR(128) NOT NULL COMMENT '机器指纹',
  platform VARCHAR(32) NOT NULL COMMENT '操作系统',
  hostname VARCHAR(128) COMMENT '主机名',
  
  activated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '激活时间',
  last_seen_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '最后在线时间',
  
  UNIQUE KEY uniq_activation (license_id, machine_id),
  INDEX idx_license_id (license_id),
  INDEX idx_machine_id (machine_id),
  
  CONSTRAINT fk_activations_license 
    FOREIGN KEY (license_id) REFERENCES licenses(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='设备激活记录';

-- ============================================
-- 4. 使用日志
-- ============================================
CREATE TABLE IF NOT EXISTS usage_logs (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  
  license_id BIGINT COMMENT '卡密 ID',
  action VARCHAR(32) NOT NULL COMMENT '操作: activate/verify/inject/revoke',
  
  -- 请求信息
  machine_id VARCHAR(128) COMMENT '机器指纹',
  ip_address VARCHAR(64) COMMENT 'IP 地址',
  user_agent TEXT COMMENT 'User Agent',
  
  -- 结果
  success BOOLEAN NOT NULL DEFAULT TRUE COMMENT '是否成功',
  error_message VARCHAR(255) COMMENT '错误信息',
  
  -- 时间
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  
  INDEX idx_license_id (license_id),
  INDEX idx_action (action),
  INDEX idx_created_at (created_at),
  INDEX idx_machine_id (machine_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='使用日志';

-- ============================================
-- 5. 管理员表
-- ============================================
CREATE TABLE IF NOT EXISTS admins (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  
  email VARCHAR(128) UNIQUE NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  role VARCHAR(32) NOT NULL DEFAULT 'admin' COMMENT '角色',
  
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_login_at DATETIME DEFAULT NULL COMMENT '最后登录时间',
  
  INDEX idx_email (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='管理员表';

-- ============================================
-- 6. 统计表（日统计）
-- ============================================
CREATE TABLE IF NOT EXISTS statistics (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  
  date DATE NOT NULL UNIQUE COMMENT '日期',
  
  -- 卡密统计
  total_licenses INT NOT NULL DEFAULT 0 COMMENT '总卡密数',
  active_licenses INT NOT NULL DEFAULT 0 COMMENT '激活中的卡密',
  expired_licenses INT NOT NULL DEFAULT 0 COMMENT '已过期的卡密',
  pending_licenses INT NOT NULL DEFAULT 0 COMMENT '未激活的卡密',
  
  -- 操作统计
  new_activations INT NOT NULL DEFAULT 0 COMMENT '新激活数',
  total_verifications INT NOT NULL DEFAULT 0 COMMENT '验证次数',
  failed_verifications INT NOT NULL DEFAULT 0 COMMENT '验证失败次数',
  
  -- Token 统计
  available_tokens INT NOT NULL DEFAULT 0 COMMENT '可用 Token 数',
  
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  
  INDEX idx_date (date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='每日统计';

-- ============================================
-- 7. 系统配置表
-- ============================================
CREATE TABLE IF NOT EXISTS system_config (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  
  config_key VARCHAR(64) NOT NULL UNIQUE COMMENT '配置键',
  config_value TEXT COMMENT '配置值',
  description VARCHAR(255) COMMENT '描述',
  
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  
  INDEX idx_key (config_key)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='系统配置';

-- ============================================
-- 初始化配置
-- ============================================
INSERT INTO system_config (config_key, config_value, description) VALUES
('email_domain', 'll222.com', '邮箱域名'),
('encryption_enabled', 'true', '是否启用 Token 加密'),
('max_verify_failures', '10', '最大验证失败次数（限流）')
ON DUPLICATE KEY UPDATE config_value = VALUES(config_value);
