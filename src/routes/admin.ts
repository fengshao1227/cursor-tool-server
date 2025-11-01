import { Router } from 'express'
import jwt from 'jsonwebtoken'
import bcrypt from 'bcryptjs'
import { z } from 'zod'
import { queryOne, queryAll, insert, update, transaction } from '../db.js'
import { config } from '../config.js'
import { generateLicenseKey, generateRandomEmail, encryptToken, decryptToken, getLicensePrefix } from '../crypto.js'

const router = Router()

// ============================================
// JWT 认证中间件
// ============================================

function signAdminToken(email: string): string {
  return jwt.sign({ sub: email, role: 'admin' }, config.jwtSecret, { expiresIn: '7d' })
}

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
// 管理员认证
// ============================================

/**
 * POST /v1/admin/login
 * 管理员登录
 */
router.post('/login', async (req, res) => {
  try {
    const body = z.object({ 
      email: z.string().email(), 
      password: z.string().min(4)
    }).parse(req.body)

    const admin = await queryOne<any>(
      'SELECT * FROM admins WHERE email = ? LIMIT 1',
      [body.email]
    )

    if (!admin) {
      return res.status(401).json({ error: 'INVALID_CREDENTIALS', message: '邮箱或密码错误' })
    }

    // 临时：支持明文密码或 bcrypt
    let ok = false
    if (admin.password_hash.startsWith('$2')) {
      // bcrypt hash
      ok = await bcrypt.compare(body.password, admin.password_hash)
    } else {
      // 明文密码（临时）
      ok = body.password === admin.password_hash
    }
    
    if (!ok) {
      return res.status(401).json({ error: 'INVALID_CREDENTIALS', message: '邮箱或密码错误' })
    }

    // 更新最后登录时间
    await update('UPDATE admins SET last_login_at = NOW() WHERE id = ?', [admin.id])

    const token = signAdminToken(body.email)
    res.json({ 
      success: true,
      token,
      admin: {
        email: admin.email,
        role: admin.role
      }
    })
  } catch (error: any) {
    res.status(400).json({ error: 'BAD_REQUEST', message: error.message })
  }
})

// ============================================
// Cursor Token 管理
// ============================================

/**
 * POST /v1/admin/tokens
 * 添加 Cursor Token
 */
router.post('/tokens', requireAuth, async (req, res) => {
  try {
    const body = z.object({
      token: z.string().min(10),
      note: z.string().max(255).optional(),
      maxAssignments: z.number().int().positive().optional(),
      isExclusive: z.boolean().optional().default(false)
    }).parse(req.body)

    // 加密 Token
    const { encrypted, iv } = encryptToken(body.token)

    const tokenId = await insert(
      `INSERT INTO cursor_tokens (token_encrypted, token_iv, note, max_assignments, is_exclusive, added_by) 
       VALUES (?, ?, ?, ?, ?, ?)`,
      [encrypted, iv, body.note || null, body.maxAssignments || null, body.isExclusive, req.admin]
    )

    res.json({ 
      success: true, 
      data: { id: tokenId }
    })
  } catch (error: any) {
    res.status(400).json({ error: 'BAD_REQUEST', message: error.message })
  }
})

/**
 * GET /v1/admin/tokens
 * 获取 Token 列表
 */
router.get('/tokens', requireAuth, async (req, res) => {
  try {
    const { status } = req.query

    let sql = `
      SELECT id, status, assigned_count, max_assignments, is_exclusive, is_consumed, note, added_by, created_at, last_used_at
      FROM cursor_tokens
    `
    const params: any[] = []

    if (status) {
      sql += ' WHERE status = ?'
      params.push(status)
    }

    sql += ' ORDER BY created_at DESC'

    const tokens = await queryAll<any>(sql, params)

    // 统计信息
    const stats = await queryOne<any>(`
      SELECT 
        COUNT(*) as total,
        SUM(CASE WHEN status = 'available' THEN 1 ELSE 0 END) as available,
        SUM(CASE WHEN status = 'in_use' THEN 1 ELSE 0 END) as in_use,
        SUM(CASE WHEN status = 'exhausted' THEN 1 ELSE 0 END) as exhausted,
        SUM(CASE WHEN is_exclusive = TRUE AND is_consumed = FALSE THEN 1 ELSE 0 END) as available_exclusive
      FROM cursor_tokens
    `)

    res.json({
      success: true,
      data: tokens,
      stats
    })
  } catch (error: any) {
    res.status(400).json({ error: 'BAD_REQUEST', message: error.message })
  }
})

/**
 * DELETE /v1/admin/tokens/:id
 * 删除 Token
 */
router.delete('/tokens/:id', requireAuth, async (req, res) => {
  try {
    const id = Number(req.params.id)
    
    // 检查是否有卡密在使用
    const count = await queryOne<any>(
      'SELECT COUNT(*) as count FROM licenses WHERE cursor_token_id = ?',
      [id]
    )

    if (count && count.count > 0) {
      return res.status(400).json({ 
        error: 'TOKEN_IN_USE', 
        message: `有 ${count.count} 个卡密正在使用此 Token，无法删除` 
      })
    }

    await update('DELETE FROM cursor_tokens WHERE id = ?', [id])
    
    res.json({ success: true })
  } catch (error: any) {
    res.status(400).json({ error: 'BAD_REQUEST', message: error.message })
  }
})

/**
 * PUT /v1/admin/tokens/:id/status
 * 更新 Token 状态
 */
router.put('/tokens/:id/status', requireAuth, async (req, res) => {
  try {
    const id = Number(req.params.id)
    const body = z.object({
      status: z.enum(['available', 'disabled'])
    }).parse(req.body)

    await update('UPDATE cursor_tokens SET status = ? WHERE id = ?', [body.status, id])
    
    res.json({ success: true })
  } catch (error: any) {
    res.status(400).json({ error: 'BAD_REQUEST', message: error.message })
  }
})

// ============================================
// 卡密管理
// ============================================

/**
 * POST /v1/admin/licenses/generate
 * 批量生成卡密
 */
router.post('/licenses/generate', requireAuth, async (req, res) => {
  try {
    const body = z.object({
      count: z.number().int().min(1).max(1000),
      validDays: z.number().int().min(0).max(3650),
      maxDevices: z.number().int().min(1).max(10).default(1),
      note: z.string().max(255).optional(),
      useExclusiveToken: z.boolean().optional().default(false)
    }).parse(req.body)

    let availableTokens: any[] = []

    if (body.useExclusiveToken) {
      // 独占模式：获取独占且未消耗的 Token
      availableTokens = await queryAll<any>(
        `SELECT id FROM cursor_tokens 
         WHERE is_exclusive = TRUE 
         AND is_consumed = FALSE
         AND status = 'available'
         ORDER BY created_at ASC
         LIMIT ?`,
        [body.count]
      )
      
      if (availableTokens.length < body.count) {
        return res.status(400).json({ 
          error: 'INSUFFICIENT_EXCLUSIVE_TOKENS', 
          message: `可用独占 Token 不足，需要 ${body.count} 个，当前只有 ${availableTokens.length} 个` 
        })
      }
    } else {
      // 普通模式：获取非独占的可用 Token
      availableTokens = await queryAll<any>(
        `SELECT id FROM cursor_tokens 
         WHERE (is_exclusive = FALSE OR is_exclusive IS NULL)
         AND status = 'available' 
         AND (max_assignments IS NULL OR assigned_count < max_assignments)
         ORDER BY assigned_count ASC
         LIMIT ?`,
        [body.count]
      )
      
      if (availableTokens.length < body.count) {
        return res.status(400).json({ 
          error: 'INSUFFICIENT_TOKENS', 
          message: `可用 Token 不足，需要 ${body.count} 个，当前只有 ${availableTokens.length} 个` 
        })
      }
    }

    // 批量生成卡密
    const licenses = await transaction(async (conn) => {
      const results = []

      for (let i = 0; i < body.count; i++) {
        const licenseKey = generateLicenseKey()
        const cursorEmail = generateRandomEmail()
        const tokenId = availableTokens[i].id

        const [result] = await conn.query<any>(
          `INSERT INTO licenses 
           (license_key, cursor_token_id, cursor_email, valid_days, max_devices, note, created_by) 
           VALUES (?, ?, ?, ?, ?, ?, ?)`,
          [licenseKey, tokenId, cursorEmail, body.validDays, body.maxDevices, body.note || null, req.admin]
        )

        if (body.useExclusiveToken) {
          // 独占模式：标记 Token 为已消耗，状态改为 exhausted
          await conn.query(
            'UPDATE cursor_tokens SET is_consumed = TRUE, status = "exhausted", assigned_count = assigned_count + 1 WHERE id = ?',
            [tokenId]
          )
        } else {
          // 普通模式：只增加分配计数
          await conn.query(
            'UPDATE cursor_tokens SET assigned_count = assigned_count + 1 WHERE id = ?',
            [tokenId]
          )
        }

        results.push({
          id: result.insertId,
          licenseKey,
          cursorEmail,
          validDays: body.validDays,
          maxDevices: body.maxDevices,
          exclusive: body.useExclusiveToken
        })
      }

      return results
    })

    res.json({ 
      success: true, 
      data: licenses,
      message: `成功生成 ${licenses.length} 个${body.useExclusiveToken ? '独占' : '普通'}卡密`
    })
  } catch (error: any) {
    res.status(400).json({ error: 'BAD_REQUEST', message: error.message })
  }
})

/**
 * GET /v1/admin/licenses
 * 查询卡密列表
 */
router.get('/licenses', requireAuth, async (req, res) => {
  try {
    const { 
      status, 
      search, 
      page = '1', 
      limit = '20' 
    } = req.query

    const pageNum = Math.max(1, Number(page))
    const limitNum = Math.min(100, Math.max(1, Number(limit)))
    const offset = (pageNum - 1) * limitNum

    // 构建查询
    let whereClause = 'WHERE 1=1'
    const params: any[] = []

    if (status) {
      whereClause += ' AND l.status = ?'
      params.push(status)
    }

    if (search) {
      whereClause += ' AND (l.license_key LIKE ? OR l.cursor_email LIKE ? OR l.note LIKE ?)'
      const searchPattern = `%${search}%`
      params.push(searchPattern, searchPattern, searchPattern)
    }

    // 查询总数
    const totalResult = await queryOne<any>(
      `SELECT COUNT(*) as total FROM licenses l ${whereClause}`,
      params
    )

    // 查询列表
    const licenses = await queryAll<any>(
      `SELECT 
        l.*,
        (SELECT COUNT(*) FROM activations a WHERE a.license_id = l.id) as device_count
       FROM licenses l
       ${whereClause}
       ORDER BY l.created_at DESC
       LIMIT ? OFFSET ?`,
      [...params, limitNum, offset]
    )

    // 统计信息
    const stats = await queryOne<any>(`
      SELECT 
        COUNT(*) as total,
        SUM(CASE WHEN status = 'pending' THEN 1 ELSE 0 END) as pending,
        SUM(CASE WHEN status = 'active' THEN 1 ELSE 0 END) as active,
        SUM(CASE WHEN status = 'expired' THEN 1 ELSE 0 END) as expired,
        SUM(CASE WHEN status = 'revoked' THEN 1 ELSE 0 END) as revoked
      FROM licenses
    `)

    res.json({
      success: true,
      data: licenses,
      pagination: {
        page: pageNum,
        limit: limitNum,
        total: totalResult?.total || 0,
        pages: Math.ceil((totalResult?.total || 0) / limitNum)
      },
      stats
    })
  } catch (error: any) {
    res.status(400).json({ error: 'BAD_REQUEST', message: error.message })
  }
})

/**
 * GET /v1/admin/licenses/:id
 * 获取卡密详情
 */
router.get('/licenses/:id', requireAuth, async (req, res) => {
  try {
    const id = Number(req.params.id)

    const license = await queryOne<any>(
      `SELECT l.*, ct.status as token_status
       FROM licenses l
       LEFT JOIN cursor_tokens ct ON l.cursor_token_id = ct.id
       WHERE l.id = ?`,
      [id]
    )

    if (!license) {
      return res.status(404).json({ error: 'NOT_FOUND', message: '卡密不存在' })
    }

    // 获取激活记录
    const activations = await queryAll<any>(
      'SELECT * FROM activations WHERE license_id = ? ORDER BY last_seen_at DESC',
      [id]
    )

    // 获取使用日志
    const logs = await queryAll<any>(
      'SELECT * FROM usage_logs WHERE license_id = ? ORDER BY created_at DESC LIMIT 50',
      [id]
    )

    res.json({
      success: true,
      data: {
        ...license,
        activations,
        logs
      }
    })
  } catch (error: any) {
    res.status(400).json({ error: 'BAD_REQUEST', message: error.message })
  }
})

/**
 * PUT /v1/admin/licenses/:id/status
 * 更新卡密状态（禁用/启用）
 */
router.put('/licenses/:id/status', requireAuth, async (req, res) => {
  try {
    const id = Number(req.params.id)
    const body = z.object({
      status: z.enum(['active', 'revoked'])
    }).parse(req.body)

    await update('UPDATE licenses SET status = ? WHERE id = ?', [body.status, id])
    
    res.json({ success: true, message: '状态已更新' })
  } catch (error: any) {
    res.status(400).json({ error: 'BAD_REQUEST', message: error.message })
  }
})

/**
 * DELETE /v1/admin/licenses/:id
 * 删除卡密
 */
router.delete('/licenses/:id', requireAuth, async (req, res) => {
  try {
    const id = Number(req.params.id)
    
    await transaction(async (conn) => {
      // 获取 token_id
      const [license] = await conn.query<any[]>(
        'SELECT cursor_token_id FROM licenses WHERE id = ?',
        [id]
      )

      if (license[0]?.cursor_token_id) {
        // 减少 Token 分配计数
        await conn.query(
          'UPDATE cursor_tokens SET assigned_count = assigned_count - 1 WHERE id = ?',
          [license[0].cursor_token_id]
        )
      }

      // 删除卡密（会级联删除 activations）
      await conn.query('DELETE FROM licenses WHERE id = ?', [id])
    })
    
    res.json({ success: true, message: '卡密已删除' })
  } catch (error: any) {
    res.status(400).json({ error: 'BAD_REQUEST', message: error.message })
  }
})

/**
 * POST /v1/admin/licenses/:id/unbind
 * 解绑设备
 */
router.post('/licenses/:id/unbind', requireAuth, async (req, res) => {
  try {
    const id = Number(req.params.id)
    const body = z.object({
      machineId: z.string()
    }).parse(req.body)

    await update(
      'DELETE FROM activations WHERE license_id = ? AND machine_id = ?',
      [id, body.machineId]
    )
    
    res.json({ success: true, message: '设备已解绑' })
  } catch (error: any) {
    res.status(400).json({ error: 'BAD_REQUEST', message: error.message })
  }
})

// ============================================
// 统计数据
// ============================================

/**
 * GET /v1/admin/statistics
 * 获取统计数据
 */
router.get('/statistics', requireAuth, async (req, res) => {
  try {
    // 今日统计
    const today = await queryOne<any>(`
      SELECT 
        COUNT(*) as total_licenses,
        SUM(CASE WHEN status = 'active' THEN 1 ELSE 0 END) as active_licenses,
        SUM(CASE WHEN status = 'pending' THEN 1 ELSE 0 END) as pending_licenses,
        SUM(CASE WHEN DATE(activated_at) = CURDATE() THEN 1 ELSE 0 END) as today_activations
      FROM licenses
    `)

    // Token 统计
    const tokenStats = await queryOne<any>(`
      SELECT 
        COUNT(*) as total,
        SUM(CASE WHEN status = 'available' THEN 1 ELSE 0 END) as available,
        SUM(assigned_count) as total_assigned
      FROM cursor_tokens
    `)

    // 最近7天激活趋势
    const weeklyActivations = await queryAll<any>(`
      SELECT 
        DATE(activated_at) as date,
        COUNT(*) as count
      FROM licenses
      WHERE activated_at >= DATE_SUB(CURDATE(), INTERVAL 7 DAY)
      GROUP BY DATE(activated_at)
      ORDER BY date DESC
    `)

    // 最近使用日志
    const recentLogs = await queryAll<any>(`
      SELECT 
        ul.*,
        l.license_key
      FROM usage_logs ul
      LEFT JOIN licenses l ON ul.license_id = l.id
      ORDER BY ul.created_at DESC
      LIMIT 20
    `)

    res.json({
      success: true,
      data: {
        overview: {
          ...today,
          ...tokenStats
        },
        weeklyActivations,
        recentLogs
      }
    })
  } catch (error: any) {
    res.status(400).json({ error: 'BAD_REQUEST', message: error.message })
  }
})

/**
 * GET /v1/admin/dashboard
 * 仪表盘数据
 */
router.get('/dashboard', requireAuth, async (req, res) => {
  try {
    // 卡密统计
    const licenseStats = await queryOne<any>(`
      SELECT 
        COUNT(*) as total,
        SUM(CASE WHEN status = 'pending' THEN 1 ELSE 0 END) as pending,
        SUM(CASE WHEN status = 'active' THEN 1 ELSE 0 END) as active,
        SUM(CASE WHEN status = 'expired' THEN 1 ELSE 0 END) as expired,
        SUM(CASE WHEN DATE(created_at) = CURDATE() THEN 1 ELSE 0 END) as today_created,
        SUM(CASE WHEN DATE(activated_at) = CURDATE() THEN 1 ELSE 0 END) as today_activated
      FROM licenses
    `)

    // Token 统计
    const tokenStats = await queryOne<any>(`
      SELECT 
        COUNT(*) as total,
        SUM(CASE WHEN status = 'available' THEN 1 ELSE 0 END) as available
      FROM cursor_tokens
    `)

    // 今日验证次数
    const todayVerifications = await queryOne<any>(`
      SELECT 
        COUNT(*) as total,
        SUM(CASE WHEN success = 1 THEN 1 ELSE 0 END) as success,
        SUM(CASE WHEN success = 0 THEN 1 ELSE 0 END) as failed
      FROM usage_logs
      WHERE action = 'verify' AND DATE(created_at) = CURDATE()
    `)

    // 最近激活的卡密
    const recentActivations = await queryAll<any>(`
      SELECT license_key, cursor_email, activated_at, expires_at
      FROM licenses
      WHERE activated_at IS NOT NULL
      ORDER BY activated_at DESC
      LIMIT 10
    `)

    res.json({
      success: true,
      data: {
        licenseStats,
        tokenStats,
        todayVerifications: todayVerifications || { total: 0, success: 0, failed: 0 },
        recentActivations
      }
    })
  } catch (error: any) {
    res.status(400).json({ error: 'BAD_REQUEST', message: error.message })
  }
})

export default router
