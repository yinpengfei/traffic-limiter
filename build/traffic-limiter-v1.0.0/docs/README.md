# 流量限制器 (Traffic Limiter)

自动监控云主机流量使用情况，在流量接近限制时自动限速，避免流量超标导致断网。

## 功能特性

- ✅ 自动监控流量使用情况（基于 vnstat）
- ✅ 分级限速（警告限速 + 严格限速）
- ✅ 支持自定义流量重置日（非自然月）
- ✅ 手动查询、设置、重置流量
- ✅ 开机自动恢复限速规则
- ✅ 日志轮转
- ✅ 邮件 + 钉钉通知

## 快速开始

### 1. 安装

```bash
# 解压
tar -zxvf traffic-limiter-v1.0.0.tar.gz
cd traffic-limiter-v1.0.0

# 安装
sudo ./install.sh
```

### 2. 初始化配置

安装过程中会引导你配置：
- 网卡名称
- 流量限制（GB）
- 重置日（1-28）
- 通知方式（可选）

### 3. 查看状态

```bash
traffic_ctl status
```

## 使用说明

### 查看流量状态

```bash
traffic_ctl status
```

输出示例：

```
==========================================
        流量使用情况
==========================================

网卡: eth0
计费周期: 每月 15 日
上次重置: 2026-06
下次重置: 2026-07-15

流量限制: 1024 GB
已用流量: 850.500 GB (83.1%)
剩余流量: 173.500 GB (16.9%)

用量: [####################------------] 83.1%

==========================================
        当前限速状态
==========================================
未启用限速 (正常)
```

### 常用命令

```bash
# 查看状态
traffic_ctl status

# 设置已用流量（校准用）
traffic_ctl set-used 500

# 手动重置（续费后）
traffic_ctl reset

# 手动限速
traffic_ctl limit 10mbit

# 取消限速
traffic_ctl unlimit

# 编辑配置
traffic_ctl config edit

# 配置钉钉通知
traffic_ctl dingtalk

# 查看日志
traffic_ctl log 100
```

## 配置说明

### 配置文件

`/etc/traffic_limiter.conf`

### 主要配置项

```bash
# 基础配置
INTERFACE="eth0"               # 网卡名称
TOTAL_LIMIT_GB=1024            # 流量限制（GB）
RESET_DAY=15                   # 每月重置日

# 限速阈值
WARNING_REMAINING_PERCENT=10   # 剩余 10% 时警告限速
CRITICAL_REMAINING_GB=10       # 剩余 10GB 时严格限速
WARNING_RATE="10mbit"          # 警告限速速率
CRITICAL_RATE="500kbit"        # 严格限速速率

# 通知配置
NOTIFY_ENABLED=true
NOTIFY_EMAIL="admin@example.com"
NOTIFY_DINGTALK_WEBHOOK="https://oapi.dingtalk.com/..."
```

详细配置说明请查看 [CONFIG.md](docs/CONFIG.md)

## 工作原理

### 流量统计

1. 使用 `vnstat` 监控网卡流量
2. 记录计费周期开始时的基准值
3. 每次检查时计算当期用量

### 限速逻辑

```
循环检查（每 10 分钟）:
  |
  +-> 流量已用尽 (剩余 <= 0GB)?
  |     |-> 是: 限速到 CRITICAL_RATE
  |     |-> 否: 继续
  |
  +-> 剩余 < CRITICAL_REMAINING_GB?
  |     |-> 是: 限速到 CRITICAL_RATE
  |     |-> 否: 继续
  |
  +-> 剩余% < WARNING_REMAINING_PERCENT?
  |     |-> 是: 限速到 WARNING_RATE
  |     |-> 否: 取消限速
```

### 自动重置

- 每天检查是否是重置日
- 如果是重置日且本月未重置，则重置基准值
- 自动取消限速规则

## 系统要求

- Linux 系统（CentOS 7+, Ubuntu 16.04+）
- root 权限
- 网卡支持 traffic control (tc)

## 定时任务

安装后会自动设置定时任务（每 10 分钟检查一次）：

```bash
sudo crontab -l
# 应该看到:
*/10 * * * * /usr/local/bin/traffic_limiter.sh >> /var/log/traffic_limiter.log 2>&1
```

如果需要修改检查频率：

```bash
sudo crontab -e
# 改为每 30 分钟:
*/30 * * * * /usr/local/bin/traffic_limiter.sh
```

## 文档

- [配置说明](docs/CONFIG.md) - 详细配置说明
- [常见问题](docs/FAQ.md) - FAQ
- [故障排查](docs/TROUBLESHOOTING.md) - 问题排查指南

## 卸载

```bash
sudo ./uninstall.sh
```

## 许可证

MIT License

## 支持

如有问题，请查看文档或提交 Issue。
