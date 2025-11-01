# 多Token绑定功能使用说明

## 功能概述

现在支持一个卡密关联多个Cursor Token，这样客户端可以获取多个账号Token，实现一卡多号的功能。

## 新增特性

### 1. 独占模式默认勾选

在"Token管理"页面添加Token后，"独占模式"复选框会保持勾选状态，方便连续添加多个独占Token。

### 2. 多Token选择功能

在"卡密管理"页面生成卡密时，可以手动选择多个Token绑定到一个卡密：

- 点击"🔽 展开 手动选择Token（可选多个）"按钮
- 勾选需要绑定的Token（支持多选）
- 生成卡密时，每个卡密都会绑定所有选择的Token

### 3. 客户端返回多Token

客户端调用激活/验证接口时，会收到所有绑定的Token：

```json
{
  "success": true,
  "data": {
    "cursorToken": "token1...",           // 兼容旧版本，返回第一个Token
    "cursorTokens": [                      // 新增：所有Token列表
      "token1...",
      "token2...",
      "token3..."
    ],
    "cursorEmail": "xxx@ll222.com",
    "expiresAt": "2024-12-31T23:59:59.999Z",
    "remainingDays": 30
  }
}
```

## 使用步骤

### 第一步：运行数据库迁移

首先需要执行数据库迁移脚本，创建`license_tokens`关联表：

```bash
# 连接到MySQL数据库
mysql -u root -p

# 执行迁移脚本
source migration-multi-token.sql
```

或者直接在MySQL客户端中执行：

```bash
mysql -u root -p license_db < migration-multi-token.sql
```

### 第二步：添加Token

1. 登录管理后台
2. 进入"Token管理"页面
3. 添加多个独占Token（勾选"🔒 独占模式"）
4. 添加成功后，复选框会保持勾选状态，方便连续添加

### 第三步：生成多Token卡密

#### 方式一：手动选择Token（推荐）

1. 进入"卡密管理"页面
2. 点击"🔽 展开 手动选择Token（可选多个）"
3. 勾选需要绑定的Token（可以选择多个）
4. 设置卡密数量、有效期等参数
5. 点击"生成卡密"

生成后，**每个卡密都会绑定所有选择的Token**。

#### 方式二：自动分配（传统方式）

1. 不展开Token选择器
2. 勾选"🔒 使用独占Token"（或取消勾选使用普通Token）
3. 设置卡密数量、有效期等参数
4. 点击"生成卡密"

生成后，每个卡密只绑定一个Token。

### 第四步：客户端使用

客户端调用激活或验证接口时，会自动返回所有绑定的Token：

```javascript
// 激活卡密
const response = await fetch('/v1/licenses/activate', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    licenseKey: 'YOUR-LICENSE-KEY',
    machineId: 'YOUR-MACHINE-ID'
  })
})

const data = await response.json()
console.log('所有Token:', data.data.cursorTokens)
// 输出: ['token1...', 'token2...', 'token3...']

// 可以将这些Token注入到不同的Cursor账号中
```

## 数据库变更

新增了`license_tokens`关联表：

```sql
CREATE TABLE license_tokens (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  license_id BIGINT NOT NULL,
  cursor_token_id BIGINT NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  
  UNIQUE KEY uniq_license_token (license_id, cursor_token_id),
  FOREIGN KEY (license_id) REFERENCES licenses(id) ON DELETE CASCADE,
  FOREIGN KEY (cursor_token_id) REFERENCES cursor_tokens(id) ON DELETE CASCADE
)
```

## API变更

### 生成卡密接口

`POST /v1/admin/licenses/generate`

新增请求参数：

```typescript
{
  count: number              // 生成数量
  validDays: number          // 有效天数
  maxDevices: number         // 最大设备数
  note?: string              // 备注
  useExclusiveToken: boolean // 使用独占Token
  selectedTokenIds?: number[] // 新增：手动选择的Token ID列表
}
```

### 激活/验证接口

响应数据新增`cursorTokens`字段：

```typescript
{
  success: true,
  data: {
    cursorToken: string      // 兼容旧版本，第一个Token
    cursorTokens: string[]   // 新增：所有Token列表
    cursorEmail: string
    expiresAt: string
    remainingDays: number
  }
}
```

## 使用场景示例

### 场景1：一卡多号

生成一个卡密，绑定3个Token，客户端可以在Cursor软件中切换使用这3个账号。

**操作步骤：**
1. 添加3个独占Token
2. 生成卡密时，选择这3个Token
3. 生成1个卡密（count=1）
4. 客户端激活后会收到3个Token

### 场景2：批量售卖多号卡密

生成10个卡密，每个卡密都绑定5个Token。

**操作步骤：**
1. 添加50个独占Token
2. 生成卡密时，选择5个Token
3. 生成10个卡密（count=10）
4. 每个卡密都会绑定这5个Token

## 注意事项

1. **数据迁移是必须的**：首次使用前必须执行`migration-multi-token.sql`脚本
2. **独占Token消耗**：选择独占Token后，这些Token会被标记为已消耗
3. **兼容性**：保持了`cursorToken`字段的向后兼容，旧客户端仍然可以正常工作
4. **Token状态**：被禁用（disabled）的Token不会返回给客户端
5. **删除卡密**：删除卡密时，关联的Token记录也会自动删除（CASCADE）

## 故障排除

### 问题1：生成卡密时提示"可用独占Token不足"

**解决方案：**
- 检查是否有足够的独占Token
- 确保Token状态为"available"且未被消耗
- 或者使用手动选择Token的方式

### 问题2：客户端只能看到一个Token

**解决方案：**
- 检查客户端是否使用了新的`cursorTokens`字段
- 旧版本客户端需要升级以支持多Token功能

### 问题3：迁移脚本执行失败

**解决方案：**
- 确保数据库连接正常
- 检查是否有表`license_tokens`已存在
- 查看MySQL错误日志获取详细信息

## 更新日志

**2024-11-01**
- ✅ 新增多Token绑定功能
- ✅ Token Manager添加后保持独占模式勾选
- ✅ 卡密生成界面支持手动选择多个Token
- ✅ 激活/验证接口返回所有绑定的Token
- ✅ 创建数据库迁移脚本

