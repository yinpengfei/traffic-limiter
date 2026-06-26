# 配置说明

## 配置文件位置

`/etc/traffic_limiter.conf`

---

## 配置项详解

### 基础配置

| 配置项 | 说明 | 默认值 | 示例 |
|--------|------|--------|------|
| `INTERFACE` | 网卡名称 | `eth0` | `eth0`, `ens3` |
| `TOTAL_LIMIT_GB` | 流量限制（GB） | `1024` | `1024`, `500` |
| `RESET_DAY` | 每月重置日 | `1` | `1`-`28` |

**如何查看网卡名称？**

```bash
ip addr
```

---

### 限速阈值

| 配置项 | 说明 | 默认值 | 示例 |
|--------|------|--------|------|
| `WARNING_REMAINING_PERCENT` | 剩余百分比阈值（低于此值触发警告限速） | `10` | `10`, `20` |
| `CRITICAL_REMAINING_GB` | 剩余流量阈值（低于此值触发严格限速） | `10` | `10`, `5` |
| `WARNING_RATE` | 警告限速速率 | `10mbit` | `10mbit`, `5mbit` |
| `CRITICAL_RATE` | 严格限速速率 | `500kbit` | `500kbit`, `1mbit` |

**限速逻辑：**

```
剩余百分比 < WARNING_REMAINING_PERCENT  →  应用 WARNING_RATE
        或
剩余流量 < CRITICAL_REMAINING_GB      →  应用 CRITICAL_RATE
```

**示例：**

假设配置：
- `TOTAL_LIMIT_GB=1024`
- `WARNING_REMAINING_PERCENT=10`（剩余 10%）
- `CRITICAL_REMAINING_GB=10`（剩余 10GB）
- `WARNING_RATE="10mbit"`
- `CRITICAL_RATE="500kbit"`

触发条件：
1. 已用 922GB（剩余 102GB，10%）→ 限速 10Mbit
2. 已用 1014GB（剩余 10GB）→ 限速 500Kbit
3. 已用 1024GB（剩余 0GB）→ 限速 500Kbit

---

### 文件路径

| 配置项 | 说明 | 默认值 |
|--------|------|--------|
| `BASELINE_FILE` | 基准流量文件 | `/var/lib/traffic_baseline` |
| `STATE_FILE` | 状态文件 | `/var/lib/traffic_state` |
| `LOG_FILE` | 日志文件 | `/var/log/traffic_limiter.log` |

**通常不需要修改这些路径。**

---

### 通知配置

| 配置项 | 说明 | 默认值 | 示例 |
|--------|------|--------|------|
| `NOTIFY_ENABLED` | 是否启用通知 | `false` | `true`, `false` |
| `NOTIFY_EMAIL` | 通知邮箱 | `""` | `admin@example.com` |
| `NOTIFY_DINGTALK_WEBHOOK` | 钉钉 Webhook | `""` | `https://oapi.dingtalk.com/...` |

#### 钉钉通知配置

1. 在钉钉群中点击 `群设置` -> `机器人`
2. 点击 `添加机器人` -> `自定义`
3. 设置机器人名称和图标
4. 复制 Webhook 地址（格式：`https://oapi.dingtalk.com/robot/send?access_token=xxx`）
5. 在配置文件中设置 `NOTIFY_DINGTALK_WEBHOOK`

**或使用命令配置：**

```bash
traffic_ctl dingtalk
```

---

## 完整配置示例

```bash
# ============ 基础配置 ============
INTERFACE="eth0"
TOTAL_LIMIT_GB=1024
RESET_DAY=15

# ============ 限速阈值 ============
WARNING_REMAINING_PERCENT=10
CRITICAL_REMAINING_GB=10
WARNING_RATE="10mbit"
CRITICAL_RATE="500kbit"

# ============ 文件路径 ============
BASELINE_FILE="/var/lib/traffic_baseline"
STATE_FILE="/var/lib/traffic_state"
LOG_FILE="/var/log/traffic_limiter.log"

# ============ 通知配置 ============
NOTIFY_ENABLED=true
NOTIFY_EMAIL="admin@example.com"
NOTIFY_DINGTALK_WEBHOOK="https://oapi.dingtalk.com/robot/send?access_token=xxx"
```

---

## 修改配置

### 方法 1：手动编辑

```bash
vi /etc/traffic_limiter.conf
```

### 方法 2：使用命令

```bash
traffic_ctl config edit
```

### 方法 3：重新初始化

```bash
traffic_limiter_init.sh
```

---

## 速率单位说明

Linux tc 命令支持的速率单位：

| 单位 | 说明 | 示例 |
|------|------|------|
| `bit` | 比特/秒 | `10mbit` = 10 Mbps |
| `kbit` | K比特/秒 | `500kbit` = 500 Kbps |
| `mbit` | M比特/秒 | `10mbit` = 10 Mbps |
| `gbit` | G比特/秒 | `1gbit` = 1 Gbps |

**注意：**
- 小写 `b` = bit（比特）
- 大写 `B` = Byte（字节）
- 1 Byte = 8 bit

**常用速率：**
- `10mbit` = 10 Mbps = 1.25 MB/s
- `5mbit` = 5 Mbps = 625 KB/s
- `1mbit` = 1 Mbps = 125 KB/s
- `500kbit` = 500 Kbps = 62.5 KB/s

---

## 常见问题

### Q: 如何临时调整限速速率？

**A:** 手动修改配置后重启服务：

```bash
vi /etc/traffic_limiter.conf
# 修改 WARNING_RATE="20mbit"
traffic_ctl limit 20mbit  # 立即生效
```

### Q: 如何永久关闭限速？

**A:** 修改配置或禁用通知：

```bash
# 方法1: 设置很大的流量限制
vi /etc/traffic_limiter.conf
# 修改 TOTAL_LIMIT_GB=999999

# 方法2: 取消限速
traffic_ctl unlimit
```

### Q: 钉钉通知收不到？

**A:** 检查以下几点：

1. Webhook 地址是否正确
2. 机器人是否被禁用
3. 网络是否能访问钉钉服务器
4. 使用测试命令：`traffic_ctl notify "测试消息"`

---

## 下一步

- [返回文档首页](README.md)
- [查看 FAQ](FAQ.md)
- [故障排查](TROUBLESHOOTING.md)
