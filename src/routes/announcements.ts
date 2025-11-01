import { Router } from 'express'
import { z } from 'zod'
import { queryOne, queryAll, insert, update } from '../db.js'
import jwt from 'jsonwebtoken'
import { config } from '../config.js'

const router = Router()

// ============================================
// 类型定义
// ============================================

interface Announcement {
  id: string
  title: string
  content: string
  type: 'info' | 'warning' | 'error' | 'success'
  priority: number
  platforms?: string[] | null
  start_time?: string | null
  end_time?: string | null
  dismissible: boolean
  auto_show: boolean
  url?: string | null
  enabled: boolean
  created_at: string
  updated_at: string
  created_by?: string | null
}

// ============================================
// 辅助函数
// ============================================

/**
 * 转换公告数据（MySQL BOOLEAN 返回 0/1，需要转换为 boolean）
 */
function transformAnnouncement(announcement: any): any {
  if (!announcement) return null
  
  // 解析 JSON 字段
  if (announcement.platforms) {
    try {
      announcement.platforms = JSON.parse(announcement.platforms)
    } catch (e) {
      announcement.platforms = null
    }
  }
  
  // MySQL BOOLEAN 类型返回 0/1，转换为 boolean
  announcement.dismissible = Boolean(announcement.dismissible)
  announcement.auto_show = Boolean(announcement.auto_show)
  announcement.enabled = Boolean(announcement.enabled)
  
  return announcement
}

// ============================================
// JWT 认证中间件
// ============================================

function requireAuth(req: any, res: any, next: any) {
  const header = req.headers.authorization || ''
  const token = header.startsWith('Bearer ') ? header.slice(7) : null
  
  if (!token) {
    return res.status(401).json({ error: 'UNAUTHORIZED', message: '未登录' })
  }
  
  try {
    const payload = jwt.verify(token, config.jwtSecret) as any
    req.admin = payload.sub
    next()
  } catch {
    return res.status(401).json({ error: 'UNAUTHORIZED', message: 'Token 无效或已过期' })
  }
}

// ============================================
// 用户端接口
// ============================================

/**
 * GET /v1/announcement/current
 * 获取当前公告（用户端）
 */
router.get('/current', async (req, res) => {
  try {
    const { platform } = req.query
    
    let sql = `
      SELECT id, title, content, type, priority, platforms, 
             start_time AS startTime, end_time AS endTime,
             dismissible, auto_show AS autoShow, url,
             created_at AS createdAt, updated_at AS updatedAt
      FROM announcements
      WHERE enabled = true
        AND (start_time IS NULL OR start_time <= NOW())
        AND (end_time IS NULL OR end_time >= NOW())
    `
    const params: any[] = []
    
    // 如果指定了平台，添加平台过滤
    if (platform && typeof platform === 'string') {
      sql += ' AND (platforms IS NULL OR JSON_CONTAINS(platforms, ?))'
      params.push(JSON.stringify(platform))
    }
    
    sql += ' ORDER BY priority DESC, created_at DESC LIMIT 1'
    
    const announcement = await queryOne<any>(sql, params)
    
    res.json({
      success: true,
      data: transformAnnouncement(announcement)
    })
  } catch (error: any) {
    res.status(500).json({ 
      success: false,
      message: '获取公告失败', 
      error: 'INTERNAL_ERROR' 
    })
  }
})

// ============================================
// 管理端接口
// ============================================

/**
 * GET /v1/announcement/admin/list
 * 获取公告列表（管理端）
 */
router.get('/admin/list', requireAuth, async (req, res) => {
  try {
    const announcements = await queryAll<any>(
      `SELECT * FROM announcements 
       ORDER BY priority DESC, created_at DESC`
    )
    
    // 转换数据
    const transformedAnnouncements = announcements.map(transformAnnouncement)
    
    res.json({
      success: true,
      data: transformedAnnouncements
    })
  } catch (error: any) {
    res.status(400).json({ 
      error: 'BAD_REQUEST', 
      message: error.message 
    })
  }
})

/**
 * GET /v1/announcement/admin/:id
 * 获取公告详情（管理端）
 */
router.get('/admin/:id', requireAuth, async (req, res) => {
  try {
    const { id } = req.params
    
    const announcement = await queryOne<any>(
      'SELECT * FROM announcements WHERE id = ?',
      [id]
    )
    
    if (!announcement) {
      return res.status(404).json({ 
        error: 'NOT_FOUND', 
        message: '公告不存在' 
      })
    }
    
    res.json({
      success: true,
      data: transformAnnouncement(announcement)
    })
  } catch (error: any) {
    res.status(400).json({ 
      error: 'BAD_REQUEST', 
      message: error.message 
    })
  }
})

/**
 * POST /v1/announcement/admin
 * 创建公告（管理端）
 */
router.post('/admin', requireAuth, async (req, res) => {
  try {
    const body = z.object({
      id: z.string().min(1).max(50),
      title: z.string().min(1).max(200),
      content: z.string().min(1),
      type: z.enum(['info', 'warning', 'error', 'success']).default('info'),
      priority: z.number().int().min(0).max(100).default(50),
      platforms: z.array(z.string()).optional(),
      startTime: z.string().optional(),
      endTime: z.string().optional(),
      dismissible: z.boolean().default(true),
      autoShow: z.boolean().default(true),
      url: z.string().max(500).optional(),
      enabled: z.boolean().default(true)
    }).parse(req.body)
    
    // 检查 ID 是否已存在
    const existing = await queryOne<any>(
      'SELECT id FROM announcements WHERE id = ?',
      [body.id]
    )
    
    if (existing) {
      return res.status(400).json({ 
        error: 'DUPLICATE_ID', 
        message: '公告 ID 已存在' 
      })
    }
    
    // 插入公告
    await insert(
      `INSERT INTO announcements 
       (id, title, content, type, priority, platforms, start_time, end_time, 
        dismissible, auto_show, url, enabled, created_by) 
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        body.id,
        body.title,
        body.content,
        body.type,
        body.priority,
        body.platforms ? JSON.stringify(body.platforms) : null,
        body.startTime || null,
        body.endTime || null,
        body.dismissible,
        body.autoShow,
        body.url || null,
        body.enabled,
        req.admin
      ]
    )
    
    res.json({ 
      success: true, 
      message: '公告创建成功',
      data: { id: body.id }
    })
  } catch (error: any) {
    res.status(400).json({ 
      error: 'BAD_REQUEST', 
      message: error.message 
    })
  }
})

/**
 * PUT /v1/announcement/admin/:id
 * 更新公告（管理端）
 */
router.put('/admin/:id', requireAuth, async (req, res) => {
  try {
    const { id } = req.params
    
    const body = z.object({
      title: z.string().min(1).max(200),
      content: z.string().min(1),
      type: z.enum(['info', 'warning', 'error', 'success']),
      priority: z.number().int().min(0).max(100),
      platforms: z.array(z.string()).optional().nullable(),
      startTime: z.string().optional().nullable(),
      endTime: z.string().optional().nullable(),
      dismissible: z.boolean(),
      autoShow: z.boolean(),
      url: z.string().max(500).optional().nullable(),
      enabled: z.boolean()
    }).parse(req.body)
    
    // 检查公告是否存在
    const existing = await queryOne<any>(
      'SELECT id FROM announcements WHERE id = ?',
      [id]
    )
    
    if (!existing) {
      return res.status(404).json({ 
        error: 'NOT_FOUND', 
        message: '公告不存在' 
      })
    }
    
    // 更新公告
    await update(
      `UPDATE announcements 
       SET title = ?, content = ?, type = ?, priority = ?, platforms = ?,
           start_time = ?, end_time = ?, dismissible = ?, auto_show = ?,
           url = ?, enabled = ?, updated_at = NOW()
       WHERE id = ?`,
      [
        body.title,
        body.content,
        body.type,
        body.priority,
        body.platforms ? JSON.stringify(body.platforms) : null,
        body.startTime || null,
        body.endTime || null,
        body.dismissible,
        body.autoShow,
        body.url || null,
        body.enabled,
        id
      ]
    )
    
    res.json({ 
      success: true, 
      message: '公告更新成功' 
    })
  } catch (error: any) {
    res.status(400).json({ 
      error: 'BAD_REQUEST', 
      message: error.message 
    })
  }
})

/**
 * DELETE /v1/announcement/admin/:id
 * 删除公告（管理端）
 */
router.delete('/admin/:id', requireAuth, async (req, res) => {
  try {
    const { id } = req.params
    
    const result = await update(
      'DELETE FROM announcements WHERE id = ?',
      [id]
    )
    
    if (result === 0) {
      return res.status(404).json({ 
        error: 'NOT_FOUND', 
        message: '公告不存在' 
      })
    }
    
    res.json({ 
      success: true, 
      message: '公告删除成功' 
    })
  } catch (error: any) {
    res.status(400).json({ 
      error: 'BAD_REQUEST', 
      message: error.message 
    })
  }
})

/**
 * PUT /v1/announcement/admin/:id/toggle
 * 切换公告启用状态（管理端）
 */
router.put('/admin/:id/toggle', requireAuth, async (req, res) => {
  try {
    const { id } = req.params
    
    // 获取当前状态
    const announcement = await queryOne<any>(
      'SELECT enabled FROM announcements WHERE id = ?',
      [id]
    )
    
    if (!announcement) {
      return res.status(404).json({ 
        error: 'NOT_FOUND', 
        message: '公告不存在' 
      })
    }
    
    // 切换状态
    const newStatus = !announcement.enabled
    await update(
      'UPDATE announcements SET enabled = ?, updated_at = NOW() WHERE id = ?',
      [newStatus, id]
    )
    
    res.json({ 
      success: true, 
      message: `公告已${newStatus ? '启用' : '禁用'}`,
      data: { enabled: newStatus }
    })
  } catch (error: any) {
    res.status(400).json({ 
      error: 'BAD_REQUEST', 
      message: error.message 
    })
  }
})

export default router

