# 流量限制器 (Traffic Limiter)

自动监控云主机流量使用情况，在流量接近限制时自动限速，避免流量超标导致断网。

## 功能特性

- ✅ 自动监控流量使用情况
- ✅ 分级限速（警告限速 + 严格限速）
- ✅ 支持自定义流量重置日（非自然月）
- ✅ 手动查询、设置、重置流量
- ✅ 开机自动恢复限速规则
- ✅ 日志轮转
- ✅ 邮件/Webhook 通知（可选）

## 快速开始

### 1. 安装

```bash
# 解压
tar -zxvf traffic-limiter-v1.0.0.tar.gz
cd traffic-limiter-v1.0.0

# 安装
./install.sh
```

### 2. 查看状态

```bash
traffic_ctl status
```

### 3. 常用命令

```bash
traffic_ctl status              # 查看流量状态
traffic_ctl set-used 500        # 设置已用流量
traffic_ctl reset               # 重置流量统计
traffic_ctl limit 10mbit        # 手动限速
traffic_ctl unlimit             # 取消限速
traffic_ctl config edit         # 编辑配置
traffic_ctl log 100             # 查看日志
```

## 文档

- [完整文档](docs/README.md) - 详细使用说明
- [配置说明](docs/CONFIG.md) - 配置文件详解
- [常见问题](docs/FAQ.md) - FAQ
- [故障排查](docs/TROUBLESHOOTING.md) - 问题排查指南

## 系统要求

- Linux 系统（CentOS 7+, Ubuntu 16.04+）
- root 权限
- 网卡支持 traffic control (tc)

## 许可证

MIT License
