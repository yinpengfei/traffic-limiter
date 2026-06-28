#!/bin/bash

# ========================================
# 流量限制器 - 安装脚本
# 用法: sudo ./install.sh
# ========================================

set -e

echo "=========================================="
echo "      流量限制器 - 安装程序"
echo "=========================================="
echo ""

# 检查 root 权限
if [ "$EUID" -ne 0 ]; then 
    echo "错误: 请使用 root 权限运行"
    echo "用法: sudo ./install.sh"
    exit 1
fi

# 检测系统类型
if [ -f /etc/redhat-release ]; then
    OS="centos"
    echo "检测到系统: CentOS/RHEL"
elif [ -f /etc/debian_version ]; then
    OS="ubuntu"
    echo "检测到系统: Ubuntu/Debian"
else
    echo "警告: 未能识别系统类型，将尝试通用安装"
    OS="unknown"
fi
echo ""

# 安装依赖
echo "步骤 1/6: 安装依赖..."
if [ "$OS" = "centos" ]; then
    yum install -y vnstat jq bc iproute-tc 2>/dev/null || echo "警告: 部分依赖安装失败，请手动检查"
elif [ "$OS" = "ubuntu" ]; then
    apt update
    apt install -y vnstat jq bc iproute2 2>/dev/null || echo "警告: 部分依赖安装失败，请手动检查"
fi
echo "✓ 依赖安装完成"
echo ""

# 复制脚本
echo "步骤 2/6: 安装脚本..."
mkdir -p /usr/local/bin
cp scripts/traffic_limiter.sh /usr/local/bin/traffic_limiter.sh
cp scripts/traffic_query.sh /usr/local/bin/traffic_query.sh
cp scripts/traffic_ctl.sh /usr/local/bin/traffic_ctl
cp scripts/traffic_limiter_init.sh /usr/local/bin/traffic_limiter_init.sh
cp scripts/traffic_daily_report.sh /usr/local/bin/traffic_daily_report.sh

chmod +x /usr/local/bin/traffic_limiter.sh
chmod +x /usr/local/bin/traffic_query.sh
chmod +x /usr/local/bin/traffic_ctl
chmod +x /usr/local/bin/traffic_limiter_init.sh
chmod +x /usr/local/bin/traffic_daily_report.sh
echo "✓ 脚本安装完成"
echo ""

# 复制配置文件
echo "步骤 3/6: 安装配置文件..."
if [ ! -f /etc/traffic_limiter.conf ]; then
    cp config/traffic_limiter.conf.template /etc/traffic_limiter.conf
    echo "✓ 配置文件已创建: /etc/traffic_limiter.conf"
else
    echo "配置文件已存在，跳过"
    echo "  如需重置配置，请手动编辑 /etc/traffic_limiter.conf"
fi
echo ""

# 复制 systemd 服务
echo "步骤 4/6: 安装 systemd 服务..."
if [ -d /etc/systemd/system ]; then
    cp systemd/traffic-limiter-restore.service /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable traffic-limiter-restore.service 2>/dev/null || true
    echo "✓ systemd 服务已安装"
else
    echo "警告: 未找到 systemd，跳过服务安装"
fi
echo ""

# 复制日志轮转配置
echo "步骤 5/6: 安装日志轮转..."
if [ -d /etc/logrotate.d ]; then
    cp logrotate/traffic_limiter /etc/logrotate.d/traffic_limiter
    echo "✓ 日志轮转已配置"
else
    echo "警告: 未找到 logrotate，跳过配置"
fi
echo ""

# 运行初始化
echo "步骤 6/6: 初始化配置..."
echo ""
read -p "是否现在运行初始化配置? (y/n, 推荐 y): " DO_INIT
if [ "$DO_INIT" = "y" ]; then
    bash /usr/local/bin/traffic_limiter_init.sh
else
    echo "跳过初始化"
    echo "  请稍后运行: sudo traffic_limiter_init.sh"
fi
echo ""

# 设置定时任务
echo "=========================================="
echo "      安装完成！"
echo "=========================================="
echo ""
echo "下一步操作:"
echo ""
echo "1. 如果跳过了初始化，请运行:"
echo "   sudo traffic_limiter_init.sh"
echo ""
echo "2. 设置定时任务（每 10 分钟检查一次）:"
echo "   sudo crontab -e"
echo "   添加: */10 * * * * /usr/local/bin/traffic_limiter.sh"
echo ""
echo "3. 查看流量状态:"
echo "   traffic_ctl status"
echo ""
echo "4. 配置钉钉通知（可选）:"
echo "   traffic_ctl dingtalk"
echo ""
echo "5. 立即发送一次流量日报测试:"
echo "   traffic_ctl report"
echo ""
echo "6. 修改日报发送时间（默认每天 01:00）:"
echo "   traffic_ctl report-time 08:00"
echo ""
echo "7. 查看文档:"
echo "   cat docs/README.md"
echo ""

# 询问是否立即设置 crontab
read -p "是否现在设置定时任务? (y/n): " SET_CRON
if [ "$SET_CRON" = "y" ]; then
    # 流量监控（每10分钟）
    if crontab -l 2>/dev/null | grep -q "traffic_limiter.sh"; then
        echo "定时监控任务已存在，跳过"
    else
        (crontab -l 2>/dev/null; echo "*/10 * * * * /usr/local/bin/traffic_limiter.sh >> /var/log/traffic_limiter.log 2>&1") | crontab -
        echo "✓ 流量监控定时任务已设置（每 10 分钟）"
    fi

    # 每日日报
    # 读取配置中的日报时间，默认 01:00
    REPORT_HOUR=1
    REPORT_MINUTE=0
    if [ -f /etc/traffic_limiter.conf ]; then
        _h=$(grep "^DAILY_REPORT_HOUR=" /etc/traffic_limiter.conf | cut -d= -f2)
        _m=$(grep "^DAILY_REPORT_MINUTE=" /etc/traffic_limiter.conf | cut -d= -f2)
        [ -n "$_h" ] && REPORT_HOUR=$_h
        [ -n "$_m" ] && REPORT_MINUTE=$_m
    fi

    if crontab -l 2>/dev/null | grep -q "traffic_daily_report.sh"; then
        echo "每日日报任务已存在，跳过"
    else
        (crontab -l 2>/dev/null; echo "$REPORT_MINUTE $REPORT_HOUR * * * /usr/local/bin/traffic_daily_report.sh >> /var/log/traffic_limiter.log 2>&1") | crontab -
        printf "✓ 每日流量日报已设置（每天 %02d:%02d 发送）\n" "$REPORT_HOUR" "$REPORT_MINUTE"
        echo "  提示: 使用 traffic_ctl report-time HH:MM 修改发送时间"
    fi
fi

echo ""
echo "安装日志:"
echo "  主日志: /var/log/traffic_limiter.log"
echo "  系统日志: journalctl -u traffic-limiter-restore.service"
echo ""
