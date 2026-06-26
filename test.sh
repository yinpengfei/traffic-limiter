#!/bin/bash

# ========================================
# 流量限制器 - 测试脚本
# 用途: 模拟各种流量场景，验证逻辑正确性
# 用法: sudo ./test.sh
# ========================================

echo "=========================================="
echo "      流量限制器 - 测试脚本"
echo "=========================================="
echo ""

# 检查 root 权限
if [ "$EUID" -ne 0 ]; then 
    echo "错误: 请使用 root 权限运行"
    exit 1
fi

# 测试配置
TEST_INTERFACE="eth0"
TEST_LIMIT_GB=100
TEST_RESET_DAY=15

echo "测试配置:"
echo "  网卡: $TEST_INTERFACE"
echo "  流量限制: ${TEST_LIMIT_GB} GB"
echo "  重置日: 每月 ${TEST_RESET_DAY} 日"
echo ""

# 创建测试配置文件
cat > /tmp/traffic_limiter_test.conf << EOF
INTERFACE="$TEST_INTERFACE"
TOTAL_LIMIT_GB=$TEST_LIMIT_GB
RESET_DAY=$TEST_RESET_DAY
WARNING_REMAINING_PERCENT=10
CRITICAL_REMAINING_GB=10
WARNING_RATE="10mbit"
CRITICAL_RATE="500kbit"
BASELINE_FILE="/tmp/traffic_baseline_test"
STATE_FILE="/tmp/traffic_state_test"
LOG_FILE="/tmp/traffic_limiter_test.log"
NOTIFY_ENABLED=false
NOTIFY_EMAIL=""
NOTIFY_DINGTALK_WEBHOOK=""
EOF

echo "=========================================="
echo " 测试 1: 流量充足（应该不限速）"
echo "=========================================="
echo "模拟: 已用 50GB / 100GB (50%)"
echo "$TEST_LIMIT_GB" > /tmp/traffic_baseline_test
echo "50" > /tmp/traffic_baseline_test  # 基准值
echo "LAST_RESET=$(date +%Y-%m)" > /tmp/traffic_state_test

# 注意: 这个测试需要真实的 vnstat 数据
# 这里只是演示测试框架

echo ""
echo "=========================================="
echo " 测试 2: 剩余 10%（应该警告限速）"
echo "=========================================="
echo "模拟: 已用 90GB / 100GB (90%)"
echo "预期: 限速到 10mbit"
echo ""

echo "=========================================="
echo " 测试 3: 剩余 10GB（应该严格限速）"
echo "=========================================="
echo "模拟: 已用 90GB / 100GB (剩余 10GB)"
echo "预期: 限速到 500kbit"
echo ""

echo "=========================================="
echo " 测试 4: 流量用尽（应该严格限速）"
echo "=========================================="
echo "模拟: 已用 100GB / 100GB (剩余 0GB)"
echo "预期: 限速到 500kbit"
echo ""

echo "=========================================="
echo " 测试 5: 重置日检查"
echo "=========================================="
TODAY=$(date +%d | sed 's/^0*//')
if [ "$TODAY" -eq "$TEST_RESET_DAY" ]; then
    echo "今天是重置日，应该触发重置"
else
    echo "今天 ($TODAY) 不是重置日 ($TEST_RESET_DAY)"
fi
echo ""

echo "=========================================="
echo " 测试 6: tc 限速规则"
echo "=========================================="
echo "测试应用限速..."
tc qdisc del dev $TEST_INTERFACE root 2>/dev/null
if tc qdisc add dev $TEST_INTERFACE root handle 1: htb default 10 2>/dev/null; then
    if tc class add dev $TEST_INTERFACE parent 1: classid 1:10 htb rate 10mbit ceil 10mbit 2>/dev/null; then
        echo "✓ htb 限速规则已应用"
        tc qdisc show dev $TEST_INTERFACE
        tc class show dev $TEST_INTERFACE
    fi
else
    echo "htb 不可用，尝试 tbf..."
    if tc qdisc add dev $TEST_INTERFACE root tbf rate 10mbit burst 32kbit latency 400ms 2>/dev/null; then
        echo "✓ tbf 限速规则已应用"
        tc qdisc show dev $TEST_INTERFACE
    else
        echo "✗ 无法应用限速规则"
    fi
fi

echo ""
echo "清除测试规则..."
tc qdisc del dev $TEST_INTERFACE root 2>/dev/null
echo "✓ 限速规则已清除"
echo ""

echo "=========================================="
echo " 测试 7: 配置文件验证"
echo "=========================================="
if [ -f "/etc/traffic_limiter.conf" ]; then
    echo "✓ 配置文件存在"
    echo "当前配置:"
    grep -v "^#" /etc/traffic_limiter.conf | grep -v "^$"
else
    echo "✗ 配置文件不存在"
fi
echo ""

echo "=========================================="
echo " 测试 8: 依赖检查"
echo "=========================================="
for cmd in vnstat jq bc ip tc; do
    if command -v $cmd &> /dev/null; then
        echo "✓ $cmd 已安装"
    else
        echo "✗ $cmd 未安装"
    fi
done
echo ""

echo "=========================================="
echo "      测试完成"
echo "=========================================="
echo ""
echo "清理测试文件..."
rm -f /tmp/traffic_limiter_test.conf
rm -f /tmp/traffic_baseline_test
rm -f /tmp/traffic_state_test
rm -f /tmp/traffic_limiter_test.log
echo "✓ 清理完成"
echo ""

echo "提示: 要完整测试，请在真实服务器上运行:"
echo "  1. 安装: sudo ./install.sh"
echo "  2. 查看状态: traffic_ctl status"
echo "  3. 手动测试限速: traffic_ctl limit 10mbit"
echo "  4. 检查 tc 规则: tc qdisc show dev eth0"
echo ""
