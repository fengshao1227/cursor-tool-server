import { Router } from 'express'
import rateLimit from 'express-rate-limit'
import { z } from 'zod'
import { queryOne, queryAll, insert, update, transaction } from '../db.js'
import { decryptToken } from '../crypto.js'

const router = Router()

// 限流：60秒内最多60次请求
const limiter = rateLimit({ 
  windowMs: 60_000, 
  max: 60,
  message: { error: 'TOO_MANY_REQUESTS', message: '请求过于频繁，请稍后再试' }
})
router.use(limiter)

// ============================================
// 类型定义
// ============================================

interface License {
  id: number
  license_key: string
  cursor_token_id: number | null
  cursor_email: string
  valid_days: number
  activated_at: string | null
  expires_at: string | null
  status: 'pending' | 'active' | 'expired' | 'revoked'
  max_devices: number
}

interface CursorToken {
  id: number
  token_encrypted: string
  token_iv: string
  status: string
}

// ============================================
// 辅助函数
// ============================================

/**
 * 记录使用日志
 */
async function logUsage(
  licenseId: number | null,
  action: string,
  machineId: string | null,
  ipAddress: string | null,
  success: boolean,
  errorMessage?: string
) {
  await insert(
    `INSERT INTO usage_logs (license_id, action, machine_id, ip_address, success, error_message) 
     VALUES (?, ?, ?, ?, ?, ?)`,
    [licenseId, action, machineId, ipAddress, success, errorMessage || null]
  )
}

/**
 * 获取客户端 IP
 */
function getClientIp(req: any): string {
  return req.headers['x-forwarded-for']?.split(',')[0] || 
         req.headers['x-real-ip'] || 
         req.connection.remoteAddress || 
         'unknown'
}

/**
 * 计算剩余天数
 */
function getRemainingDays(expiresAt: string): number {
  const now = new Date()
  const expires = new Date(expiresAt)
  const diff = expires.getTime() - now.getTime()
  return Math.ceil(diff / (1000 * 60 * 60 * 24))
}

// ============================================
// API 路由
// ============================================

/**
 * POST /v1/licenses/activate
 * 激活卡密（仅验证卡密正确性和有效期，不限制机器码）
 */
router.post('/activate', async (req, res) => {
  const ip = getClientIp(req)
  
  try {
    const body = z.object({
      licenseKey: z.string().min(10),
      machineId: z.string().optional(),
      platform: z.string().optional(),
      hostname: z.string().max(128).optional()
    }).parse(req.body)

    // 1. 查找卡密
    const license = await queryOne<License>(
      'SELECT * FROM licenses WHERE license_key = ? LIMIT 1',
      [body.licenseKey]
    )

    if (!license) {
      await logUsage(null, 'activate', body.machineId || null, ip, false, 'INVALID_KEY')
      return res.status(404).json({ 
        success: false, 
        error: 'INVALID_KEY', 
        message: '卡密不存在' 
      })
    }

    // 2. 检查状态
    if (license.status === 'revoked') {
      await logUsage(license.id, 'activate', body.machineId || null, ip, false, 'REVOKED')
      return res.status(403).json({ 
        success: false, 
        error: 'REVOKED', 
        message: '卡密已被禁用' 
      })
    }

    if (license.status === 'expired') {
      await logUsage(license.id, 'activate', body.machineId || null, ip, false, 'EXPIRED')
      return res.status(403).json({ 
        success: false, 
        error: 'EXPIRED', 
        message: '卡密已过期' 
      })
    }

    // 3. 检查过期时间
    if (license.expires_at && new Date(license.expires_at) < new Date()) {
      await update('UPDATE licenses SET status = "expired" WHERE id = ?', [license.id])
      await logUsage(license.id, 'activate', body.machineId || null, ip, false, 'EXPIRED')
      return res.status(403).json({ 
        success: false, 
        error: 'EXPIRED', 
        message: '卡密已过期' 
      })
    }

    // 4. 如果是首次激活，更新卡密状态和过期时间
    let expiresAt: Date
    if (license.status === 'pending') {
      const activatedAt = new Date()
      expiresAt = new Date(activatedAt)
      expiresAt.setDate(expiresAt.getDate() + license.valid_days)

      await update(
        `UPDATE licenses 
         SET status = 'active', activated_at = ?, expires_at = ?, last_verified_at = NOW() 
         WHERE id = ?`,
        [activatedAt, expiresAt, license.id]
      )
    } else {
      // 已激活，只更新验证时间
      await update('UPDATE licenses SET last_verified_at = NOW() WHERE id = ?', [license.id])
      expiresAt = new Date(license.expires_at!)
    }

    // 5. 获取 Cursor Token
    let cursorToken = ''
    if (license.cursor_token_id) {
      const token = await queryOne<CursorToken>(
        'SELECT token_encrypted, token_iv FROM cursor_tokens WHERE id = ?',
        [license.cursor_token_id]
      )
      if (token) {
        cursorToken = decryptToken(token.token_encrypted, token.token_iv)
      }
    }

    // 6. 记录日志
    await logUsage(license.id, 'activate', body.machineId || null, ip, true)

    // 7. 返回成功
    res.json({
      success: true,
      message: '激活成功',
      data: {
        cursorToken,
        cursorEmail: license.cursor_email,
        expiresAt: expiresAt.toISOString(),
        remainingDays: getRemainingDays(expiresAt.toISOString())
      }
    })

  } catch (error: any) {
    console.error('Activate error:', error)
    res.status(400).json({ 
      success: false, 
      error: 'BAD_REQUEST', 
      message: error.message 
    })
  }
})

/**
 * POST /v1/licenses/verify
 * 验证卡密（仅验证卡密正确性和有效期，不限制机器码）
 */
router.post('/verify', async (req, res) => {
  const ip = getClientIp(req)
  
  try {
    const body = z.object({
      licenseKey: z.string(),
      machineId: z.string().optional(),
      device: z.object({
        machineId: z.string().optional(),
        platform: z.string().optional(),
        hostname: z.string().optional()
      }).optional(),
      appVersion: z.string().optional()
    }).parse(req.body)

    const machineId = body.machineId || body.device?.machineId || null

    // 1. 查找卡密
    const license = await queryOne<License>(
      'SELECT * FROM licenses WHERE license_key = ?',
      [body.licenseKey]
    )

    if (!license) {
      await logUsage(null, 'verify', machineId, ip, false, 'INVALID_KEY')
      return res.json({ 
        valid: false, 
        error: 'INVALID_KEY', 
        message: '卡密不存在' 
      })
    }

    // 2. 检查状态
    if (license.status === 'revoked') {
      await logUsage(license.id, 'verify', machineId, ip, false, 'REVOKED')
      return res.json({ 
        valid: false, 
        error: 'REVOKED', 
        message: '卡密已被禁用' 
      })
    }

    if (license.status === 'pending') {
      await logUsage(license.id, 'verify', machineId, ip, false, 'NOT_ACTIVATED')
      return res.json({ 
        valid: false, 
        error: 'NOT_ACTIVATED', 
        message: '卡密未激活' 
      })
    }

    // 3. 检查过期
    if (license.expires_at && new Date(license.expires_at) < new Date()) {
      // 自动标记为过期
      await update('UPDATE licenses SET status = "expired" WHERE id = ?', [license.id])
      await logUsage(license.id, 'verify', machineId, ip, false, 'EXPIRED')
      return res.json({ 
        valid: false, 
        error: 'EXPIRED', 
        message: '卡密已过期' 
      })
    }

    // 4. 更新验证时间
    await update('UPDATE licenses SET last_verified_at = NOW() WHERE id = ?', [license.id])

    // 5. 获取 Cursor Token
    let cursorToken = ''
    if (license.cursor_token_id) {
      const token = await queryOne<CursorToken>(
        'SELECT token_encrypted, token_iv FROM cursor_tokens WHERE id = ?',
        [license.cursor_token_id]
      )
      if (token) {
        cursorToken = decryptToken(token.token_encrypted, token.token_iv)
      }
    }

    // 6. 记录日志
    await logUsage(license.id, 'verify', machineId, ip, true)

    // 7. 返回成功（包含 receipt 和 signature 用于离线验证）
    const receipt = {
      licenseId: license.id,
      keyPrefix: body.licenseKey.substring(0, 8),
      device: body.device || { 
        machineId: machineId || '', 
        platform: '' 
      },
      maxDevices: license.max_devices,
      expiresAt: license.expires_at!,
      issuedAt: license.activated_at || new Date().toISOString(),
      notAfter: license.expires_at || new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString()
    }

    res.json({
      valid: true,
      receipt,
      signature: '', // 这里可以生成签名，但为了简化暂时留空
      serverTime: new Date().toISOString(),
      data: {
        status: 'active',
        cursorToken,
        cursorEmail: license.cursor_email,
        expiresAt: license.expires_at,
        remainingDays: getRemainingDays(license.expires_at!)
      }
    })

  } catch (error: any) {
    console.error('Verify error:', error)
    res.status(400).json({ 
      valid: false, 
      error: 'BAD_REQUEST', 
      message: error.message 
    })
  }
})

/**
 * POST /v1/licenses/inject
 * 获取注入配置（简化版的 verify，仅验证卡密正确性和有效期）
 */
router.post('/inject', async (req, res) => {
  const ip = getClientIp(req)
  
  try {
    const body = z.object({
      licenseKey: z.string(),
      machineId: z.string().optional()
    }).parse(req.body)

    const license = await queryOne<License>(
      `SELECT l.*, ct.token_encrypted, ct.token_iv 
       FROM licenses l
       LEFT JOIN cursor_tokens ct ON l.cursor_token_id = ct.id
       WHERE l.license_key = ? AND l.status = 'active'`,
      [body.licenseKey]
    )

    if (!license) {
      await logUsage(null, 'inject', body.machineId || null, ip, false, 'INVALID_OR_INACTIVE')
      return res.status(404).json({ 
        success: false, 
        error: 'INVALID_OR_INACTIVE' 
      })
    }

    // 检查过期
    if (license.expires_at && new Date(license.expires_at) < new Date()) {
      await logUsage(license.id, 'inject', body.machineId || null, ip, false, 'EXPIRED')
      return res.status(403).json({ 
        success: false, 
        error: 'EXPIRED' 
      })
    }

    // 解密 Token
    let cursorToken = ''
    if ((license as any).token_encrypted) {
      cursorToken = decryptToken((license as any).token_encrypted, (license as any).token_iv)
    }

    await logUsage(license.id, 'inject', body.machineId || null, ip, true)

    res.json({
      success: true,
      cursorToken,
      cursorEmail: license.cursor_email
    })

  } catch (error: any) {
    console.error('Inject error:', error)
    res.status(400).json({ success: false, error: 'BAD_REQUEST' })
  }
})

export default router
