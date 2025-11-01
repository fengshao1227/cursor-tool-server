import crypto from 'crypto'

// ============================================
// Token 加密/解密
// ============================================

const ALGORITHM = 'aes-256-gcm'
const KEY_LENGTH = 32
const IV_LENGTH = 16
const AUTH_TAG_LENGTH = 16

// 从环境变量或默认值获取加密密钥
function getEncryptionKey(): Buffer {
  const key = process.env.ENCRYPTION_KEY || 'default-key-change-in-production-32chars'
  return crypto.scryptSync(key, 'salt', KEY_LENGTH)
}

/**
 * 加密 Cursor Token
 */
export function encryptToken(token: string): { encrypted: string; iv: string } {
  const iv = crypto.randomBytes(IV_LENGTH)
  const key = getEncryptionKey()
  const cipher = crypto.createCipheriv(ALGORITHM, key, iv)
  
  let encrypted = cipher.update(token, 'utf8', 'hex')
  encrypted += cipher.final('hex')
  
  const authTag = cipher.getAuthTag()
  
  return {
    encrypted: encrypted + authTag.toString('hex'),
    iv: iv.toString('hex')
  }
}

/**
 * 解密 Cursor Token
 */
export function decryptToken(encrypted: string, ivHex: string): string {
  const key = getEncryptionKey()
  const iv = Buffer.from(ivHex, 'hex')
  
  // 分离密文和认证标签
  const authTagStart = encrypted.length - (AUTH_TAG_LENGTH * 2)
  const ciphertext = encrypted.substring(0, authTagStart)
  const authTag = Buffer.from(encrypted.substring(authTagStart), 'hex')
  
  const decipher = crypto.createDecipheriv(ALGORITHM, key, iv)
  decipher.setAuthTag(authTag)
  
  let decrypted = decipher.update(ciphertext, 'hex', 'utf8')
  decrypted += decipher.final('utf8')
  
  return decrypted
}

// ============================================
// 卡密生成
// ============================================

const LICENSE_PREFIX = 'CK'  // Cursor Key
const CHARSET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789' // 移除易混淆字符

/**
 * 生成随机卡密
 * 格式: CK-XXXX-XXXX-XXXX
 */
export function generateLicenseKey(): string {
  const parts = []
  
  for (let i = 0; i < 3; i++) {
    let part = ''
    for (let j = 0; j < 4; j++) {
      const randomIndex = crypto.randomInt(0, CHARSET.length)
      part += CHARSET[randomIndex]
    }
    parts.push(part)
  }
  
  return `${LICENSE_PREFIX}-${parts.join('-')}`
}

/**
 * 获取卡密前缀（用于展示）
 */
export function getLicensePrefix(licenseKey: string): string {
  return licenseKey.substring(0, 8) // CK-XXXX
}

// ============================================
// 邮箱生成
// ============================================

/**
 * 生成随机邮箱
 * 格式: abcd@ll222.com
 */
export function generateRandomEmail(): string {
  const domain = 'll222.com'
  let username = ''
  
  for (let i = 0; i < 4; i++) {
    const randomIndex = crypto.randomInt(0, 26)
    username += String.fromCharCode(97 + randomIndex) // a-z
  }
  
  return `${username}@${domain}`
}

// ============================================
// Hash 工具
// ============================================

/**
 * SHA256 Hash
 */
export function sha256(input: string): string {
  return crypto.createHash('sha256').update(input, 'utf8').digest('hex')
}

/**
 * 生成随机字符串
 */
export function randomString(length: number): string {
  return crypto.randomBytes(Math.ceil(length / 2)).toString('hex').substring(0, length)
}

// ============================================
// 签名验证（用于 API 安全）
// ============================================

/**
 * 生成 API 签名
 */
export function generateSignature(data: any): string {
  const secret = process.env.API_SECRET || 'default-api-secret'
  const payload = JSON.stringify(data)
  return crypto.createHmac('sha256', secret).update(payload).digest('hex')
}

/**
 * 验证 API 签名
 */
export function verifySignature(data: any, signature: string): boolean {
  const expected = generateSignature(data)
  return crypto.timingSafeEqual(Buffer.from(signature), Buffer.from(expected))
}
