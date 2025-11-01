import React, { useState, useEffect } from 'react'
import axios from 'axios'
import './App.css'

const api = axios.create({ baseURL: '/v1/admin' })

// ============================================
// 类型定义
// ============================================

interface License {
  id: number
  license_key: string
  cursor_email: string
  valid_days: number
  activated_at: string | null
  expires_at: string | null
  status: 'pending' | 'active' | 'expired' | 'revoked'
  max_devices: number
  device_count: number
  note: string | null
  created_at: string
}

interface Token {
  id: number
  status: string
  assigned_count: number
  max_assignments: number | null
  is_exclusive: boolean
  is_consumed: boolean
  note: string | null
  created_at: string
}

interface DashboardData {
  licenseStats: any
  tokenStats: any
  todayVerifications: any
  recentActivations: any[]
}

// ============================================
// 登录页面
// ============================================

function LoginPage({ onLogin }: { onLogin: (token: string) => void }) {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault()
    setError('')
    setLoading(true)

    try {
      const { data } = await api.post('/login', { email, password })
      onLogin(data.token)
    } catch (err: any) {
      setError(err.response?.data?.message || '登录失败')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="login-container">
      <div className="login-box">
        <h1>🔐 License Manager</h1>
        <p className="subtitle">Cursor 卡密管理系统</p>
        
        <form onSubmit={handleLogin}>
          <div className="form-group">
            <label>邮箱</label>
            <input
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="admin@example.com"
              required
            />
          </div>

          <div className="form-group">
            <label>密码</label>
            <input
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              placeholder="••••••••"
              required
            />
          </div>

          {error && <div className="error-message">{error}</div>}

          <button type="submit" className="btn-primary" disabled={loading}>
            {loading ? '登录中...' : '登录'}
          </button>
        </form>
      </div>
    </div>
  )
}

// ============================================
// 仪表盘
// ============================================

function Dashboard({ authApi }: { authApi: any }) {
  const [data, setData] = useState<DashboardData | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    loadData()
  }, [])

  const loadData = async () => {
    try {
      const { data } = await authApi.get('/dashboard')
      setData(data.data)
    } catch (err) {
      console.error('Failed to load dashboard:', err)
    } finally {
      setLoading(false)
    }
  }

  if (loading) return <div className="loading">加载中...</div>

  return (
    <div className="dashboard">
      <h2>📊 仪表盘</h2>

      <div className="stats-grid">
        <div className="stat-card">
          <div className="stat-icon">📦</div>
          <div className="stat-content">
            <div className="stat-value">{data?.licenseStats?.total || 0}</div>
            <div className="stat-label">总卡密</div>
          </div>
        </div>

        <div className="stat-card active">
          <div className="stat-icon">✅</div>
          <div className="stat-content">
            <div className="stat-value">{data?.licenseStats?.active || 0}</div>
            <div className="stat-label">激活中</div>
          </div>
        </div>

        <div className="stat-card">
          <div className="stat-icon">⏸️</div>
          <div className="stat-content">
            <div className="stat-value">{data?.licenseStats?.pending || 0}</div>
            <div className="stat-label">未激活</div>
          </div>
        </div>

        <div className="stat-card">
          <div className="stat-icon">🔑</div>
          <div className="stat-content">
            <div className="stat-value">{data?.tokenStats?.available || 0}</div>
            <div className="stat-label">可用 Token</div>
          </div>
        </div>
      </div>

      <div className="section">
        <h3>📈 今日数据</h3>
        <div className="info-grid">
          <div className="info-item">
            <span>新增卡密:</span>
            <strong>{data?.licenseStats?.today_created || 0}</strong>
          </div>
          <div className="info-item">
            <span>今日激活:</span>
            <strong>{data?.licenseStats?.today_activated || 0}</strong>
          </div>
          <div className="info-item">
            <span>验证次数:</span>
            <strong>{data?.todayVerifications?.total || 0}</strong>
          </div>
          <div className="info-item">
            <span>验证成功:</span>
            <strong className="text-success">{data?.todayVerifications?.success || 0}</strong>
          </div>
        </div>
      </div>

      <div className="section">
        <h3>🔥 最近激活</h3>
        <div className="table-container">
          <table>
            <thead>
              <tr>
                <th>卡密</th>
                <th>邮箱</th>
                <th>激活时间</th>
                <th>过期时间</th>
              </tr>
            </thead>
            <tbody>
              {data?.recentActivations?.map((item: any) => (
                <tr key={item.license_key}>
                  <td><code>{item.license_key}</code></td>
                  <td>{item.cursor_email}</td>
                  <td>{new Date(item.activated_at).toLocaleString()}</td>
                  <td>{new Date(item.expires_at).toLocaleString()}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  )
}

// ============================================
// 卡密管理
// ============================================

function LicenseManager({ authApi }: { authApi: any }) {
  const [licenses, setLicenses] = useState<License[]>([])
  const [stats, setStats] = useState<any>(null)
  const [loading, setLoading] = useState(false)
  const [search, setSearch] = useState('')
  const [statusFilter, setStatusFilter] = useState('')
  const [page, setPage] = useState(1)
  const [total, setTotal] = useState(0)
  
  // 生成表单
  const [generating, setGenerating] = useState(false)
  const [count, setCount] = useState(10)
  const [validDays, setValidDays] = useState(7)
  const [maxDevices, setMaxDevices] = useState(1)
  const [note, setNote] = useState('')
  const [useExclusiveToken, setUseExclusiveToken] = useState(true)
  const [generated, setGenerated] = useState<any[]>([])

  useEffect(() => {
    loadLicenses()
  }, [page, statusFilter])

  const loadLicenses = async () => {
    setLoading(true)
    try {
      const { data } = await authApi.get('/licenses', {
        params: { page, limit: 20, status: statusFilter, search }
      })
      setLicenses(data.data)
      setStats(data.stats)
      setTotal(data.pagination.total)
    } catch (err) {
      console.error('Failed to load licenses:', err)
    } finally {
      setLoading(false)
    }
  }

  const handleGenerate = async (e: React.FormEvent) => {
    e.preventDefault()
    setGenerating(true)
    setGenerated([])

    try {
      const { data } = await authApi.post('/licenses/generate', {
        count,
        validDays,
        maxDevices,
        note,
        useExclusiveToken
      })
      setGenerated(data.data)
      alert(data.message || `成功生成 ${data.data.length} 个卡密！`)
      loadLicenses()
    } catch (err: any) {
      alert(err.response?.data?.message || '生成失败')
    } finally {
      setGenerating(false)
    }
  }

  const handleRevoke = async (id: number) => {
    if (!confirm('确定要禁用此卡密吗？')) return

    try {
      await authApi.put(`/licenses/${id}/status`, { status: 'revoked' })
      alert('已禁用')
      loadLicenses()
    } catch (err) {
      alert('操作失败')
    }
  }

  const handleDelete = async (id: number) => {
    if (!confirm('确定要删除此卡密吗？此操作不可恢复！')) return

    try {
      await authApi.delete(`/licenses/${id}`)
      alert('已删除')
      loadLicenses()
    } catch (err) {
      alert('删除失败')
    }
  }

  return (
    <div className="license-manager">
      <h2>🎫 卡密管理</h2>

      {/* 统计信息 */}
      {stats && (
        <div className="stats-bar">
          <span>总计: <strong>{stats.total}</strong></span>
          <span>待激活: <strong>{stats.pending}</strong></span>
          <span>激活中: <strong className="text-success">{stats.active}</strong></span>
          <span>已过期: <strong className="text-muted">{stats.expired}</strong></span>
          <span>已禁用: <strong className="text-danger">{stats.revoked}</strong></span>
        </div>
      )}

      {/* 生成卡密 */}
      <div className="section card">
        <h3>🔥 批量生成卡密</h3>
        <form onSubmit={handleGenerate} className="generate-form">
          <div className="form-row">
            <div className="form-group">
              <label>数量</label>
              <input
                type="number"
                min="1"
                max="1000"
                value={count}
                onChange={(e) => setCount(Number(e.target.value))}
                required
              />
            </div>

            <div className="form-group">
              <label>有效期（天）</label>
              <select value={validDays} onChange={(e) => setValidDays(Number(e.target.value))}>
                <option value="1">1 天</option>
                <option value="3">3 天</option>
                <option value="7">7 天</option>
                <option value="15">15 天</option>
                <option value="30">30 天</option>
                <option value="90">90 天</option>
                <option value="180">180 天</option>
                <option value="365">365 天</option>
              </select>
            </div>

            <div className="form-group">
              <label>设备数</label>
              <input
                type="number"
                min="1"
                max="10"
                value={maxDevices}
                onChange={(e) => setMaxDevices(Number(e.target.value))}
                required
              />
            </div>

            <div className="form-group flex-1">
              <label>备注</label>
              <input
                type="text"
                value={note}
                onChange={(e) => setNote(e.target.value)}
                placeholder="可选"
              />
            </div>
          </div>

          <div className="form-group">
            <label className="checkbox-label">
              <input
                type="checkbox"
                checked={useExclusiveToken}
                onChange={(e) => setUseExclusiveToken(e.target.checked)}
              />
              <span>🔒 使用独占Token（一个Token只生成一个卡密，生成后Token被消耗）</span>
            </label>
            {useExclusiveToken && stats?.available_exclusive > 0 && (
              <div className="help-text">
                ℹ️ 当前有 {stats.available_exclusive} 个可用独占Token
              </div>
            )}
          </div>

          <button type="submit" className="btn-primary" disabled={generating}>
            {generating ? '生成中...' : '生成卡密'}
          </button>
        </form>

        {/* 显示生成结果 */}
        {generated.length > 0 && (
          <div className="generated-result">
            <h4>✅ 生成成功！{generated[0]?.exclusive && ' 🔒 独占模式'}</h4>
            <div className="generated-list">
              {generated.map((item) => (
                <div key={item.id} className="generated-item">
                  <code>{item.licenseKey}</code>
                  <span className="text-muted">{item.cursorEmail}</span>
                  {item.exclusive && <span className="badge-exclusive">🔒 独占</span>}
                </div>
              ))}
            </div>
            <button
              className="btn-secondary"
              onClick={() => {
                const text = generated.map(g => g.licenseKey).join('\n')
                navigator.clipboard.writeText(text)
                alert('已复制到剪贴板')
              }}
            >
              📋 复制全部卡密
            </button>
          </div>
        )}
      </div>

      {/* 筛选和搜索 */}
      <div className="filters">
        <div className="search-box">
          <input
            type="text"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="搜索卡密、邮箱..."
          />
          <button onClick={loadLicenses} className="btn-secondary">🔍 搜索</button>
        </div>

        <select value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)}>
          <option value="">全部状态</option>
          <option value="pending">待激活</option>
          <option value="active">激活中</option>
          <option value="expired">已过期</option>
          <option value="revoked">已禁用</option>
        </select>
      </div>

      {/* 卡密列表 */}
      <div className="table-container">
        <table>
          <thead>
            <tr>
              <th>卡密</th>
              <th>邮箱</th>
              <th>状态</th>
              <th>设备</th>
              <th>有效期</th>
              <th>激活时间</th>
              <th>备注</th>
              <th>操作</th>
            </tr>
          </thead>
          <tbody>
            {loading ? (
              <tr><td colSpan={8} className="text-center">加载中...</td></tr>
            ) : licenses.length === 0 ? (
              <tr><td colSpan={8} className="text-center">暂无数据</td></tr>
            ) : (
              licenses.map((license) => (
                <tr key={license.id}>
                  <td><code>{license.license_key}</code></td>
                  <td>{license.cursor_email}</td>
                  <td>
                    <span className={`status-badge status-${license.status}`}>
                      {license.status === 'pending' && '⏸️ 待激活'}
                      {license.status === 'active' && '✅ 激活中'}
                      {license.status === 'expired' && '❌ 已过期'}
                      {license.status === 'revoked' && '🚫 已禁用'}
                    </span>
                  </td>
                  <td>{license.device_count}/{license.max_devices}</td>
                  <td>{license.valid_days} 天</td>
                  <td>
                    {license.activated_at 
                      ? new Date(license.activated_at).toLocaleDateString()
                      : '-'}
                  </td>
                  <td className="text-muted">{license.note || '-'}</td>
                  <td>
                    <div className="action-buttons">
                      {license.status === 'active' && (
                        <button
                          onClick={() => handleRevoke(license.id)}
                          className="btn-small btn-warning"
                        >
                          禁用
                        </button>
                      )}
                      <button
                        onClick={() => handleDelete(license.id)}
                        className="btn-small btn-danger"
                      >
                        删除
                      </button>
                    </div>
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>

      {/* 分页 */}
      {total > 20 && (
        <div className="pagination">
          <button
            onClick={() => setPage(p => Math.max(1, p - 1))}
            disabled={page === 1}
            className="btn-secondary"
          >
            上一页
          </button>
          <span>第 {page} 页</span>
          <button
            onClick={() => setPage(p => p + 1)}
            disabled={page * 20 >= total}
            className="btn-secondary"
          >
            下一页
          </button>
        </div>
      )}
    </div>
  )
}

// ============================================
// Token 管理
// ============================================

function TokenManager({ authApi }: { authApi: any }) {
  const [tokens, setTokens] = useState<Token[]>([])
  const [stats, setStats] = useState<any>(null)
  const [newToken, setNewToken] = useState('')
  const [note, setNote] = useState('')
  const [isExclusive, setIsExclusive] = useState(true)
  const [adding, setAdding] = useState(false)

  useEffect(() => {
    loadTokens()
  }, [])

  const loadTokens = async () => {
    try {
      const { data } = await authApi.get('/tokens')
      setTokens(data.data)
      setStats(data.stats)
    } catch (err) {
      console.error('Failed to load tokens:', err)
    }
  }

  const handleAdd = async (e: React.FormEvent) => {
    e.preventDefault()
    setAdding(true)

    try {
      await authApi.post('/tokens', { token: newToken, note, isExclusive })
      alert('Token 添加成功！')
      setNewToken('')
      setNote('')
      setIsExclusive(false)
      loadTokens()
    } catch (err: any) {
      alert(err.response?.data?.message || '添加失败')
    } finally {
      setAdding(false)
    }
  }

  const handleDelete = async (id: number) => {
    if (!confirm('确定要删除此 Token 吗？')) return

    try {
      await authApi.delete(`/tokens/${id}`)
      alert('已删除')
      loadTokens()
    } catch (err: any) {
      alert(err.response?.data?.message || '删除失败')
    }
  }

  return (
    <div className="token-manager">
      <h2>🔑 Cursor Token 管理</h2>

      {/* 统计 */}
      {stats && (
        <div className="stats-bar">
          <span>总计: <strong>{stats.total}</strong></span>
          <span>可用: <strong className="text-success">{stats.available}</strong></span>
          <span>使用中: <strong>{stats.in_use}</strong></span>
          <span>已耗尽: <strong className="text-danger">{stats.exhausted}</strong></span>
          <span>可用独占: <strong className="text-info">{stats.available_exclusive || 0}</strong></span>
        </div>
      )}

      {/* 添加 Token */}
      <div className="section card">
        <h3>➕ 添加 Token</h3>
        <form onSubmit={handleAdd}>
          <div className="form-group">
            <label>Cursor Token</label>
            <textarea
              value={newToken}
              onChange={(e) => setNewToken(e.target.value)}
              placeholder="粘贴 Cursor Token..."
              rows={3}
              required
            />
          </div>

          <div className="form-group">
            <label>备注</label>
            <input
              type="text"
              value={note}
              onChange={(e) => setNote(e.target.value)}
              placeholder="可选"
            />
          </div>

          <div className="form-group">
            <label className="checkbox-label">
              <input
                type="checkbox"
                checked={isExclusive}
                onChange={(e) => setIsExclusive(e.target.checked)}
              />
              <span>🔒 独占模式（此Token只能生成一个卡密）</span>
            </label>
            <div className="help-text">
              ℹ️ 独占Token在生成卡密后会被自动标记为已消耗，无法再次使用
            </div>
          </div>

          <button type="submit" className="btn-primary" disabled={adding}>
            {adding ? '添加中...' : '添加 Token'}
          </button>
        </form>
      </div>

      {/* Token 列表 */}
      <div className="table-container">
        <table>
          <thead>
            <tr>
              <th>ID</th>
              <th>类型</th>
              <th>状态</th>
              <th>已分配</th>
              <th>备注</th>
              <th>添加时间</th>
              <th>操作</th>
            </tr>
          </thead>
          <tbody>
            {tokens.length === 0 ? (
              <tr><td colSpan={7} className="text-center">暂无 Token</td></tr>
            ) : (
              tokens.map((token) => (
                <tr key={token.id}>
                  <td>{token.id}</td>
                  <td>
                    {token.is_exclusive ? (
                      <span className="badge-exclusive">🔒 独占</span>
                    ) : (
                      <span className="badge-normal">🔓 普通</span>
                    )}
                    {token.is_exclusive && token.is_consumed && (
                      <span className="badge-consumed"> (已消耗)</span>
                    )}
                  </td>
                  <td>
                    <span className={`status-badge status-${token.status}`}>
                      {token.status}
                    </span>
                  </td>
                  <td>
                    {token.assigned_count}
                    {token.max_assignments && ` / ${token.max_assignments}`}
                  </td>
                  <td className="text-muted">{token.note || '-'}</td>
                  <td>{new Date(token.created_at).toLocaleString()}</td>
                  <td>
                    <button
                      onClick={() => handleDelete(token.id)}
                      className="btn-small btn-danger"
                      disabled={token.is_consumed && token.is_exclusive}
                    >
                      删除
                    </button>
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
    </div>
  )
}

// ============================================
// 主应用
// ============================================

export default function App() {
  const [token, setToken] = useState<string | null>(localStorage.getItem('admin_token'))
  const [currentTab, setCurrentTab] = useState<'dashboard' | 'licenses' | 'tokens'>('dashboard')

  const authApi = React.useMemo(() => {
    return axios.create({
      baseURL: '/v1/admin',
      headers: token ? { Authorization: `Bearer ${token}` } : {}
    })
  }, [token])

  const handleLogin = (newToken: string) => {
    setToken(newToken)
    localStorage.setItem('admin_token', newToken)
  }

  const handleLogout = () => {
    setToken(null)
    localStorage.removeItem('admin_token')
  }

  if (!token) {
    return <LoginPage onLogin={handleLogin} />
  }

  return (
    <div className="app">
      {/* 顶部导航 */}
      <header className="header">
        <div className="header-left">
          <h1>🔐 License Manager</h1>
        </div>
        <div className="header-right">
          <button onClick={handleLogout} className="btn-secondary">退出登录</button>
        </div>
      </header>

      {/* 侧边栏 */}
      <div className="layout">
        <aside className="sidebar">
          <nav>
            <button
              className={currentTab === 'dashboard' ? 'active' : ''}
              onClick={() => setCurrentTab('dashboard')}
            >
              📊 仪表盘
            </button>
            <button
              className={currentTab === 'licenses' ? 'active' : ''}
              onClick={() => setCurrentTab('licenses')}
            >
              🎫 卡密管理
            </button>
            <button
              className={currentTab === 'tokens' ? 'active' : ''}
              onClick={() => setCurrentTab('tokens')}
            >
              🔑 Token 管理
            </button>
          </nav>
        </aside>

        {/* 主内容 */}
        <main className="main-content">
          {currentTab === 'dashboard' && <Dashboard authApi={authApi} />}
          {currentTab === 'licenses' && <LicenseManager authApi={authApi} />}
          {currentTab === 'tokens' && <TokenManager authApi={authApi} />}
        </main>
      </div>
    </div>
  )
}
