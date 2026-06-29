#!/bin/bash

# ========================================
# 流量限制器 - 初始化配置向导
# ========================================

echo "=========================================="
echo "      流量限制器 - 初始化配置"
echo "=========================================="
echo ""

# 检查是否是 root 用户
if [ "$EUID" -ne 0 ]; then 
    echo "错误: 请使用 root 用户运行此脚本"
    exit 1
fi

# 读取网卡名称
echo "步骤 1/6: 配置网卡"
echo "----------------------------------------"
echo "可用网卡："
ip -o link show | awk -F': ' '{print "  " $2}'
echo ""
read -p "请输入网卡名称 (默认 eth0): " INTERFACE
INTERFACE=${INTERFACE:-eth0}

# 验证网卡
if ! ip link show $INTERFACE &> /dev/null; then
    echo "错误: 网卡 $INTERFACE 不存在"
    exit 1
fi
echo "✓ 网卡设置为: $INTERFACE"
echo ""

# 读取流量限制
echo "步骤 2/6: 配置流量限制"
echo "----------------------------------------"
read -p "请输入流量限制 (单位 GB, 默认 1024): " TOTAL_LIMIT_GB
TOTAL_LIMIT_GB=${TOTAL_LIMIT_GB:-1024}
echo "✓ 流量限制设置为: ${TOTAL_LIMIT_GB} GB"
echo ""

# 读取重置日
echo "步骤 3/6: 配置流量重置日"
echo "----------------------------------------"
echo "提示: 流量重置日是每月的哪一天（根据你的购买日期）"
while true; do
    read -p "请输入重置日 (1-28, 默认 1): " RESET_DAY
    RESET_DAY=${RESET_DAY:-1}
    if [ "$RESET_DAY" -ge 1 ] && [ "$RESET_DAY" -le 28 ]; then
        echo "✓ 重置日设置为: 每月 ${RESET_DAY} 日"
        break
    else
        echo "错误: 请输入 1-28 之间的数字"
    fi
done
echo ""

# 读取警告阈值（剩余百分比）
echo "步骤 4/6: 配置警告阈值"
echo "----------------------------------------"
echo "提示: 当剩余流量百分比低于此值时，触发警告限速"
read -p "请输入警告阈值 (剩余百分比, 默认 10): " WARNING_REMAINING_PERCENT
WARNING_REMAINING_PERCENT=${WARNING_REMAINING_PERCENT:-10}
echo "✓ 警告阈值设置为: 剩余 ${WARNING_REMAINING_PERCENT}%"
echo ""

# 读取严格阈值（剩余 GB）
echo "步骤 5/6: 配置严格阈值"
echo "----------------------------------------"
echo "提示: 当剩余流量低于此值时，触发严格限速"
read -p "请输入严格阈值 (剩余 GB, 默认 10): " CRITICAL_REMAINING_GB
CRITICAL_REMAINING_GB=${CRITICAL_REMAINING_GB:-10}
echo "✓ 严格阈值设置为: 剩余 ${CRITICAL_REMAINING_GB} GB"
echo ""

# 读取限速速率
echo "步骤 6/6: 配置限速速率"
echo "----------------------------------------"
read -p "请输入警告限速速率 (默认 10mbit): " WARNING_RATE
WARNING_RATE=${WARNING_RATE:-10mbit}

read -p "请输入严格限速速率 (默认 500kbit): " CRITICAL_RATE
CRITICAL_RATE=${CRITICAL_RATE:-500kbit}
echo "✓ 限速速率设置完成"
echo ""

# 读取通知配置
echo "配置通知（可选）"
echo "----------------------------------------"
read -p "是否启用通知? (y/n, 默认 n): " NOTIFY_ENABLED
if [ "$NOTIFY_ENABLED" = "y" ]; then
    NOTIFY_ENABLED=true
    
    read -p "请输入通知邮箱 (可选): " NOTIFY_EMAIL
    
    echo ""
    echo "钉钉通知配置:"
    echo "  1. 在钉钉群中添加机器人"
    echo "  2. 选择'自定义' -> 'Webhook'"
    echo "  3. 复制 Webhook 地址"
    read -p "请输入钉钉 Webhook 地址 (可选): " NOTIFY_DINGTALK_WEBHOOK
else
    NOTIFY_ENABLED=false
    NOTIFY_EMAIL=""
    NOTIFY_DINGTALK_WEBHOOK=""
fi
echo ""

# 生成配置文件
echo "正在生成配置文件..."
cat > /etc/traffic_limiter.conf << EOF
# ============ 基础配置 ============
INTERFACE="$INTERFACE"
TOTAL_LIMIT_GB=$TOTAL_LIMIT_GB
RESET_DAY=$RESET_DAY

# ============ 限速阈值 ============
WARNING_REMAINING_PERCENT=$WARNING_REMAINING_PERCENT
CRITICAL_REMAINING_GB=$CRITICAL_REMAINING_GB
WARNING_RATE="$WARNING_RATE"
CRITICAL_RATE="$CRITICAL_RATE"

# ============ 文件路径 ============
BASELINE_FILE="/var/lib/traffic_baseline"
STATE_FILE="/var/lib/traffic_state"
LOG_FILE="/var/log/traffic_limiter.log"

# ============ 通知配置 ============
NOTIFY_ENABLED=$NOTIFY_ENABLED
NOTIFY_EMAIL="$NOTIFY_EMAIL"
NOTIFY_DINGTALK_WEBHOOK="$NOTIFY_DINGTALK_WEBHOOK"
EOF

echo "✓ 配置文件已生成: /etc/traffic_limiter.conf"
echo ""

# 初始化 vnstat
echo "正在初始化 vnstat..."
if ! systemctl is-active --quiet vnstat; then
    systemctl enable vnstat &> /dev/null
    systemctl start vnstat &> /dev/null
fi

# 等待 vnstat 收集数据
echo "等待 vnstat 收集数据（10秒）..."
sleep 10

# 初始化基准值
echo "正在初始化基准流量..."
total_gb=$(vnstat -i $INTERFACE --json 2>/dev/null | jq '.interfaces[0].traffic.total.rx + .interfaces[0].traffic.total.tx' 2>/dev/null | awk '{printf "%.3f", $1/1024/1024/1024}')
if [ -z "$total_gb" ] || [ "$total_gb" = "0.000" ]; then
    echo "警告: 无法获取 vnstat 数据，将在首次运行时设置基准值"
    total_gb=0
fi
echo "$total_gb" > /var/lib/traffic_baseline

# 初始化状态文件
echo "LAST_RESET=$(date +%Y-%m)" > /var/lib/traffic_state
echo "LAST_RESET_TIMESTAMP=$(date +%s)" >> /var/lib/traffic_state

echo ""
echo "=========================================="
echo "✓ 初始化完成！"
echo "=========================================="
echo ""
echo "配置信息:"
echo "  网卡: $INTERFACE"
echo "  流量限制: ${TOTAL_LIMIT_GB} GB"
echo "  重置日: 每月 $RESET_DAY 日"
echo "  警告阈值: 剩余 ${WARNING_REMAINING_PERCENT}%"
echo "  严格阈值: 剩余 ${CRITICAL_REMAINING_GB} GB"
echo "  基准流量: ${total_gb} GB"
echo ""
echo "下一步:"
echo "  1. 查看状态: traffic_ctl status"
echo "  2. 测试运行: traffic_ctl limit ${WARNING_RATE}"
echo "  3. 取消限速: traffic_ctl unlimit"
echo "  4. 设置定时任务: sudo crontab -e"
echo "     添加: */10 * * * * /usr/local/bin/traffic_limiter.sh"
echo ""
