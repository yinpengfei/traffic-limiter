#!/bin/bash

# 流量限制器 - 卸载脚本

echo "=========================================="
echo "      流量限制器 - 卸载程序"
echo "=========================================="
echo ""

# 检查 root 权限
if [ "$EUID" -ne 0 ]; then 
    echo "错误: 请使用 root 用户运行此脚本"
    exit 1
fi

# 取消限速
echo "正在取消限速规则..."
tc qdisc del dev $(grep "INTERFACE" /etc/traffic_limiter.conf 2>/dev/null | cut -d'"' -f2) root 2>/dev/null || true

# 停止并禁用服务
echo "正在停止服务..."
systemctl stop traffic-limiter-restore.service 2>/dev/null || true
systemctl disable traffic-limiter-restore.service 2>/dev/null || true

# 删除 systemd 服务
echo "正在删除 systemd 服务..."
rm -f /etc/systemd/system/traffic-limiter-restore.service
systemctl daemon-reload

# 删除脚本
echo "正在删除脚本..."
rm -f /usr/local/bin/traffic_limiter.sh
rm -f /usr/local/bin/traffic_query.sh
rm -f /usr/local/bin/traffic_ctl
rm -f /usr/local/bin/traffic_limiter_init.sh

# 删除配置
echo "正在删除配置文件..."
rm -f /etc/traffic_limiter.conf
rm -f /var/lib/traffic_baseline
rm -f /var/lib/traffic_state

# 删除日志轮转配置
echo "正在删除日志轮转配置..."
rm -f /etc/logrotate.d/traffic_limiter

# 删除定时任务
echo "正在删除定时任务..."
(crontab -l 2>/dev/null | grep -v "traffic_limiter.sh") | crontab -

# 询问是否删除日志
read -p "是否删除日志文件? (y/n): " DELETE_LOG
if [ "$DELETE_LOG" = "y" ]; then
    rm -f /var/log/traffic_limiter.log
    rm -f /var/log/traffic_limiter.log.*
fi

echo ""
echo "=========================================="
echo "      卸载完成！"
echo "=========================================="
echo ""
