-- ============================================
-- 在线公告系统数据表
-- ============================================

CREATE TABLE IF NOT EXISTS announcements (
  id VARCHAR(50) PRIMARY KEY,
  title VARCHAR(200) NOT NULL COMMENT '公告标题',
  content TEXT NOT NULL COMMENT '公告内容（支持多行文本）',
  type VARCHAR(20) DEFAULT 'info' COMMENT '公告类型: info/warning/error/success',
  priority INT DEFAULT 50 COMMENT '优先级（数值越大越优先显示）',
  platforms JSON COMMENT '目标平台列表，为空表示所有平台 ["windows", "mac", "linux"]',
  start_time TIMESTAMP NULL COMMENT '公告开始时间',
  end_time TIMESTAMP NULL COMMENT '公告结束时间',
  dismissible BOOLEAN DEFAULT true COMMENT '是否可关闭',
  auto_show BOOLEAN DEFAULT true COMMENT '是否自动显示',
  url VARCHAR(500) COMMENT '相关链接',
  enabled BOOLEAN DEFAULT true COMMENT '是否启用',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  created_by VARCHAR(255) COMMENT '创建者邮箱',
  INDEX idx_enabled_time (enabled, start_time, end_time),
  INDEX idx_priority (priority)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='在线公告表';

-- ============================================
-- 插入示例公告数据
-- ============================================

INSERT INTO announcements (
  id, 
  title, 
  content, 
  type, 
  priority, 
  platforms, 
  start_time,
  end_time,
  dismissible, 
  auto_show, 
  url, 
  enabled
) VALUES (
  'permission_reminder_2025',
  '⚠️ 重要提醒：请设置软件权限',
  '为确保机器码重置功能正常使用，请务必设置以下权限：\n\nWindows用户：\n• 右键点击软件，选择"以管理员身份运行"\n• 或在软件属性中勾选"以管理员身份运行此程序"\n\nmacOS用户：\n• 系统设置 → 隐私与安全性 → 完全磁盘访问权限 → 添加本软件\n• 如遇到权限问题，请先移除再重新添加\n\n未正确设置权限将导致机器码重置失败！',
  'warning',
  100,
  JSON_ARRAY('windows', 'mac'),
  '2025-11-01 00:00:00',
  '2025-12-31 23:59:59',
  true,
  true,
  NULL,
  true
) ON DUPLICATE KEY UPDATE 
  updated_at = CURRENT_TIMESTAMP;

-- ============================================
-- 查询示例
-- ============================================

-- 查询当前有效的公告（按优先级排序）
-- SELECT * FROM announcements 
-- WHERE enabled = true
--   AND (start_time IS NULL OR start_time <= NOW())
--   AND (end_time IS NULL OR end_time >= NOW())
-- ORDER BY priority DESC, created_at DESC;

-- 查询适用于 Mac 平台的公告
-- SELECT * FROM announcements 
-- WHERE enabled = true
--   AND (start_time IS NULL OR start_time <= NOW())
--   AND (end_time IS NULL OR end_time >= NOW())
--   AND (platforms IS NULL OR JSON_CONTAINS(platforms, '"mac"'))
-- ORDER BY priority DESC, created_at DESC
-- LIMIT 1;

