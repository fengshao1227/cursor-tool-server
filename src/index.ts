import express from 'express'
import helmet from 'helmet'
import morgan from 'morgan'
import cors from 'cors'
import path from 'path'
import { fileURLToPath } from 'url'
import { config } from './config.js'
import { initDb, queryOne } from './db.js'
import licensesRouter from './routes/licenses.js'
import adminRouter from './routes/admin.js'
import bcrypt from 'bcryptjs'

const __filename = fileURLToPath(import.meta.url)
const __dirname = path.dirname(__filename)

async function bootstrap() {
  await initDb()

  // Seed initial admin if configured and not present
  if (config.adminEmail && config.adminPassword) {
    const admin = await queryOne<any>(
      'SELECT id FROM admins WHERE email = ? LIMIT 1',
      [config.adminEmail]
    )
    if (!admin) {
      const hash = await bcrypt.hash(config.adminPassword, 10)
      await queryOne(
        'INSERT INTO admins (email, password_hash, role) VALUES (?, ?, ?)',
        [config.adminEmail, hash, 'admin']
      )
      // eslint-disable-next-line no-console
      console.log(`✅ Seeded admin: ${config.adminEmail}`)
    }
  }

  const app = express()
  app.disable('x-powered-by')
  
  // 禁用 helmet 的 CSP，避免资源加载问题
  app.use(helmet({
    contentSecurityPolicy: false,
    crossOriginEmbedderPolicy: false,
  }))
  
  app.use(express.json())
  app.use(morgan('combined'))

  // CORS: closed by default, allow admin SPA if hosted elsewhere via env ALLOW_ORIGIN
  const allowOrigin = process.env.ALLOW_ORIGIN
  if (allowOrigin) app.use(cors({ origin: allowOrigin, credentials: false }))

  app.get('/healthz', (_req, res) => res.json({ ok: true }))

  app.use('/v1/licenses', licensesRouter)
  app.use('/v1/admin', adminRouter)

  // Serve admin SPA if built
  const adminDist = path.join(__dirname, '../admin/dist')
  
  // 静态文件服务
  app.use('/admin', express.static(adminDist, {
    maxAge: 0, // 禁用缓存，方便调试
    etag: true,
    lastModified: true,
  }))
  
  // SPA fallback - 所有 /admin/* 路由返回 index.html
  app.get('/admin/*', (_req, res) => {
    res.sendFile(path.join(adminDist, 'index.html'))
  })

  app.listen(config.port, '0.0.0.0', () => {
    // eslint-disable-next-line no-console
    console.log(`License server listening on :${config.port}`)
    // eslint-disable-next-line no-console
    console.log(`Admin panel: http://localhost:${config.port}/admin/`)
    // eslint-disable-next-line no-console
    console.log(`Admin dist: ${adminDist}`)
  })
}

bootstrap().catch((err) => {
  // eslint-disable-next-line no-console
  console.error(err)
  process.exit(1)
})


