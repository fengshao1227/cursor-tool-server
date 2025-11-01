import mysql from 'mysql2/promise'
import { config } from './config.js'
import fs from 'fs'
import path from 'path'
import { fileURLToPath } from 'url'

const __filename = fileURLToPath(import.meta.url)
const __dirname = path.dirname(__filename)

export let pool: mysql.Pool

export async function initDb(): Promise<void> {
  pool = mysql.createPool({
    uri: config.databaseUrl,
    connectionLimit: 10,
  })

  // 读取并执行 SQL 初始化脚本
  const sqlPath = path.join(__dirname, '../init-db.sql')
  
  if (fs.existsSync(sqlPath)) {
    const sql = fs.readFileSync(sqlPath, 'utf8')
    
    // 分割多个 SQL 语句并执行
    const statements = sql
      .split(';')
      .map(s => s.trim())
      .filter(s => s.length > 0 && !s.startsWith('--'))
    
    for (const statement of statements) {
      try {
        await pool.query(statement)
      } catch (error: any) {
        // 忽略表已存在等错误
        if (!error.message.includes('already exists')) {
          console.error('SQL Error:', statement.substring(0, 100))
          throw error
        }
      }
    }
    
    console.log('✅ Database initialized successfully')
  } else {
    console.warn('⚠️  init-db.sql not found, skipping auto-initialization')
  }
}

// ============================================
// 数据库查询辅助函数
// ============================================

/**
 * 执行查询并返回第一行
 */
export async function queryOne<T>(sql: string, params?: any[]): Promise<T | null> {
  const [rows] = await pool.query<any[]>(sql, params)
  return rows[0] || null
}

/**
 * 执行查询并返回所有行
 */
export async function queryAll<T>(sql: string, params?: any[]): Promise<T[]> {
  const [rows] = await pool.query<any[]>(sql, params)
  return rows
}

/**
 * 执行插入并返回 insertId
 */
export async function insert(sql: string, params?: any[]): Promise<number> {
  const [result] = await pool.query<any>(sql, params)
  return result.insertId
}

/**
 * 执行更新并返回影响的行数
 */
export async function update(sql: string, params?: any[]): Promise<number> {
  const [result] = await pool.query<any>(sql, params)
  return result.affectedRows
}

/**
 * 事务执行
 */
export async function transaction<T>(callback: (conn: mysql.PoolConnection) => Promise<T>): Promise<T> {
  const conn = await pool.getConnection()
  try {
    await conn.beginTransaction()
    const result = await callback(conn)
    await conn.commit()
    return result
  } catch (error) {
    await conn.rollback()
    throw error
  } finally {
    conn.release()
  }
}
