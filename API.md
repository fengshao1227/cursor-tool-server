# License Server API 文档

## 📋 目录

- [客户端 API](#客户端-api)（软件调用）
- [管理后台 API](#管理后台-api)
- [错误码说明](#错误码说明)
- [集成示例](#集成示例)

---

## 客户端 API

### 1. 激活卡密

**接口**: `POST /v1/licenses/activate`

**说明**: 首次使用卡密时调用，激活卡密并绑定设备

**请求参数**:
```json
{
  "licenseKey": "CK-XXXX-XXXX-XXXX",
  "machineId": "unique-machine-id",
  "platform": "darwin",
  "hostname": "MacBook-Pro"
}
```

**成功响应**:
```json
{
  "success": true,
  "message": "激活成功",
  "data": {
    "cursorToken": "eyJhbGc...",
    "cursorEmail": "abcd@ll222.com",
    "expiresAt": "2025-11-07T00:00:00Z",
    "remainingDays": 7,
    "maxDevices": 3
  }
}
```

**错误响应**:
```json
{
  "success": false,
  "error": "DEVICE_LIMIT",
  "message": "设备数量已达上限"
}
```

---

### 2. 验证卡密

**接口**: `POST /v1/licenses/verify`

**说明**: 软件启动时调用，验证卡密是否有效

**请求参数**:
```json
{
  "licenseKey": "CK-XXXX-XXXX-XXXX",
  "machineId": "unique-machine-id"
}
```

**成功响应**:
```json
{
  "valid": true,
  "data": {
    "status": "active",
    "cursorToken": "eyJhbGc...",
    "cursorEmail": "abcd@ll222.com",
    "expiresAt": "2025-11-07T00:00:00Z",
    "remainingDays": 5
  }
}
```

**失败响应**:
```json
{
  "valid": false,
  "error": "EXPIRED",
  "message": "卡密已过期"
}
```

---

### 3. 获取注入配置

**接口**: `POST /v1/licenses/inject`

**说明**: 获取 Cursor Token 和邮箱用于注入

**请求参数**:
```json
{
  "licenseKey": "CK-XXXX-XXXX-XXXX",
  "machineId": "unique-machine-id"
}
```

**成功响应**:
```json
{
  "success": true,
  "cursorToken": "eyJhbGc...",
  "cursorEmail": "abcd@ll222.com"
}
```

---

## 管理后台 API

### 认证

所有管理后台 API 需要在请求头中携带 Token：
```
Authorization: Bearer <token>
```

### 1. 登录

**接口**: `POST /v1/admin/login`

**请求参数**:
```json
{
  "email": "admin@example.com",
  "password": "admin123"
}
```

**响应**:
```json
{
  "success": true,
  "token": "eyJhbGc...",
  "admin": {
    "email": "admin@example.com",
    "role": "admin"
  }
}
```

---

### 2. 批量生成卡密

**接口**: `POST /v1/admin/licenses/generate`

**请求参数**:
```json
{
  "count": 10,
  "validDays": 7,
  "maxDevices": 3,
  "note": "测试批次"
}
```

**响应**:
```json
{
  "success": true,
  "data": [
    {
      "id": 1,
      "licenseKey": "CK-ABCD-EFGH-IJKL",
      "cursorEmail": "abcd@ll222.com",
      "validDays": 7,
      "maxDevices": 3
    }
  ],
  "message": "成功生成 10 个卡密"
}
```

---

### 3. 查询卡密列表

**接口**: `GET /v1/admin/licenses`

**查询参数**:
- `status`: 状态筛选 (pending/active/expired/revoked)
- `search`: 搜索关键词
- `page`: 页码（默认 1）
- `limit`: 每页数量（默认 20）

**响应**:
```json
{
  "success": true,
  "data": [...],
  "pagination": {
    "page": 1,
    "limit": 20,
    "total": 100,
    "pages": 5
  },
  "stats": {
    "total": 100,
    "pending": 20,
    "active": 60,
    "expired": 15,
    "revoked": 5
  }
}
```

---

### 4. 获取卡密详情

**接口**: `GET /v1/admin/licenses/:id`

**响应**:
```json
{
  "success": true,
  "data": {
    "...": "卡密信息",
    "activations": [...],
    "logs": [...]
  }
}
```

---

### 5. 禁用/启用卡密

**接口**: `PUT /v1/admin/licenses/:id/status`

**请求参数**:
```json
{
  "status": "revoked"
}
```

---

### 6. 删除卡密

**接口**: `DELETE /v1/admin/licenses/:id`

---

### 7. 添加 Cursor Token

**接口**: `POST /v1/admin/tokens`

**请求参数**:
```json
{
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "note": "来源：账号A",
  "maxAssignments": 100
}
```

---

### 8. Token 列表

**接口**: `GET /v1/admin/tokens`

**查询参数**:
- `status`: available/in_use/exhausted/disabled

---

### 9. 删除 Token

**接口**: `DELETE /v1/admin/tokens/:id`

---

### 10. 仪表盘数据

**接口**: `GET /v1/admin/dashboard`

**响应**: 包含统计数据和最近激活记录

---

### 11. 统计数据

**接口**: `GET /v1/admin/statistics`

**响应**: 包含详细的统计信息和趋势数据

---

## 错误码说明

| 错误码 | 说明 |
|-------|------|
| `INVALID_KEY` | 卡密不存在 |
| `REVOKED` | 卡密已被禁用 |
| `EXPIRED` | 卡密已过期 |
| `NOT_ACTIVATED` | 卡密未激活 |
| `DEVICE_LIMIT` | 设备数量已达上限 |
| `DEVICE_NOT_ACTIVATED` | 此设备未激活 |
| `INSUFFICIENT_TOKENS` | 可用 Token 不足 |
| `TOKEN_IN_USE` | Token 正在使用中 |
| `UNAUTHORIZED` | 未登录或 Token 无效 |
| `BAD_REQUEST` | 请求参数错误 |
| `TOO_MANY_REQUESTS` | 请求过于频繁 |

---

## 集成示例

### JavaScript/TypeScript

```typescript
import axios from 'axios'

const API_BASE = 'http://your-server:8080/v1/licenses'

// 激活卡密
async function activateLicense(licenseKey: string, machineId: string) {
  try {
    const { data } = await axios.post(`${API_BASE}/activate`, {
      licenseKey,
      machineId,
      platform: process.platform,
      hostname: require('os').hostname()
    })
    
    if (data.success) {
      // 保存 Token 和邮箱
      localStorage.setItem('cursorToken', data.data.cursorToken)
      localStorage.setItem('cursorEmail', data.data.cursorEmail)
      return true
    }
  } catch (error) {
    console.error('激活失败:', error.response?.data)
    return false
  }
}

// 验证卡密
async function verifyLicense(licenseKey: string, machineId: string) {
  try {
    const { data } = await axios.post(`${API_BASE}/verify`, {
      licenseKey,
      machineId
    })
    
    return data.valid
  } catch (error) {
    return false
  }
}

// 使用示例
const licenseKey = 'CK-XXXX-XXXX-XXXX'
const machineId = getMachineId() // 获取机器唯一标识

// 首次激活
await activateLicense(licenseKey, machineId)

// 每次启动验证
if (await verifyLicense(licenseKey, machineId)) {
  console.log('卡密有效，启动软件')
} else {
  console.log('卡密无效，请重新激活')
}
```

### Python

```python
import requests

API_BASE = 'http://your-server:8080/v1/licenses'

def activate_license(license_key, machine_id):
    response = requests.post(f'{API_BASE}/activate', json={
        'licenseKey': license_key,
        'machineId': machine_id,
        'platform': 'darwin',
        'hostname': 'MacBook'
    })
    
    if response.ok:
        data = response.json()
        return data.get('success', False)
    return False

def verify_license(license_key, machine_id):
    response = requests.post(f'{API_BASE}/verify', json={
        'licenseKey': license_key,
        'machineId': machine_id
    })
    
    if response.ok:
        data = response.json()
        return data.get('valid', False)
    return False
```

---

## 🔐 安全建议

1. **HTTPS**: 生产环境务必使用 HTTPS
2. **限流**: 已内置限流，60秒最多60次请求
3. **Token 加密**: Cursor Token 使用 AES-256-GCM 加密存储
4. **机器指纹**: 建议使用多个硬件信息组合生成唯一标识
5. **日志审计**: 所有操作都有日志记录

---

## 📞 技术支持

如有问题，请查看：
- [部署文档](./DEPLOY.md)
- [README](./README.md)
- 服务日志: `tail -f server.log`

