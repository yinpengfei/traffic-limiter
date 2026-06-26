#!/bin/bash

# ========================================
# 流量限制器 - 流量查询工具
# 功能: 显示当前流量使用情况和限速状态
# ========================================

# 加载配置
CONFIG_FILE="/etc/traffic_limiter.conf"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "错误: 配置文件不存在: $CONFIG_FILE"
    exit 1
fi

# 默认值
INTERFACE="${INTERFACE:-eth0}"
TOTAL_LIMIT_GB="${TOTAL_LIMIT_GB:-1024}"
RESET_DAY="${RESET_DAY:-1}"
WARNING_REMAINING_PERCENT="${WARNING_REMAINING_PERCENT:-10}"
CRITICAL_REMAINING_GB="${CRITICAL_REMAINING_GB:-10}"
BASELINE_FILE="${BASELINE_FILE:-/var/lib/traffic_baseline}"
STATE_FILE="${STATE_FILE:-/var/lib/traffic_state}"

# 颜色定义
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=========================================="
echo "        流量使用情况"
echo "=========================================="
echo ""

# 读取基准值和当前值
BASELINE=$(cat $BASELINE_FILE 2>/dev/null || echo "0")
CURRENT=$(vnstat -i $INTERFACE --json 2>/dev/null | jq '.interfaces[0].traffic.total.rx + .interfaces[0].traffic.total.tx' 2>/dev/null | awk '{printf "%.3f", $1/1024/1024/1024}')
if [ -z "$CURRENT" ]; then
    CURRENT="0.000"
fi

# 计算当期用量
if [ "$BASELINE" = "0" ]; then
    USED="0.000"
else
    USED=$(echo "scale=3; $CURRENT - $BASELINE" | bc 2>/dev/null || echo "0.000")
    if [ $(echo "$USED < 0" | bc 2>/dev/null || echo "1") -eq 1 ]; then
        USED="0.000"
    fi
fi

# 计算剩余
REMAINING=$(echo "scale=3; $TOTAL_LIMIT_GB - $USED" | bc 2>/dev/null || echo "$TOTAL_LIMIT_GB")
if [ $(echo "$REMAINING < 0" | bc 2>/dev/null || echo "0") -eq 1 ]; then
    REMAINING="0.000"
fi

PERCENT=$(echo "scale=2; $USED / $TOTAL_LIMIT_GB * 100" | bc 2>/dev/null || echo "0")
REMAINING_PERCENT=$(echo "scale=2; 100 - $PERCENT" | bc 2>/dev/null | cut -d. -f1 || echo "100")

# 确保百分比在合理范围
if [ -z "$REMAINING_PERCENT" ] || [ "$REMAINING_PERCENT" -lt 0 ]; then
    REMAINING_PERCENT=0
fi
if [ "$REMAINING_PERCENT" -gt 100 ]; then
    REMAINING_PERCENT=100
fi

# 读取重置日期
LAST_RESET=$(grep "^LAST_RESET=" $STATE_FILE 2>/dev/null | cut -d= -f2 || echo "未设置")

# 计算下次重置日期
CURRENT_DAY=$(date +%d | sed 's/^0*//')
if [ "$CURRENT_DAY" -ge "$RESET_DAY" ]; then
    NEXT_RESET=$(date -d "$(date +%Y-%m)-$RESET_DAY +1 month" +%Y-%m-%d 2>/dev/null || date -v+1m +%Y-%m-${RESET_DAY} 2>/dev/null || echo "未知")
else
    NEXT_RESET=$(date +%Y-%m)-$(printf "%02d" $RESET_DAY)
fi

# 显示配置信息
echo "网卡: $INTERFACE"
echo "计费周期: 每月 $RESET_DAY 日"
echo "上次重置: $LAST_RESET"
echo "下次重置: $NEXT_RESET"
echo ""

# 显示流量信息
echo "流量限制: ${TOTAL_LIMIT_GB} GB"
echo "已用流量: ${USED} GB (${PERCENT}%)"
echo "剩余流量: ${REMAINING} GB (${REMAINING_PERCENT}%)"
echo ""

# 进度条
BAR_LENGTH=40
FILLED=$(echo "($PERCENT / 100 * $BAR_LENGTH) / 1" | bc 2>/dev/null || echo "0")
if [ -z "$FILLED" ] || [ "$FILLED" -lt 0 ]; then
    FILLED=0
fi
EMPTY=$((BAR_LENGTH - FILLED))
if [ $EMPTY -lt 0 ]; then
    EMPTY=0
fi

if [ $(echo "$PERCENT > 90" | bc 2>/dev/null || echo "0") -eq 1 ]; then
    COLOR=$RED
elif [ $(echo "$PERCENT > 80" | bc 2>/dev/null || echo "0") -eq 1 ]; then
    COLOR=$YELLOW
else
    COLOR=$GREEN
fi

printf "用量: ["
printf "${COLOR}"
for ((i=0; i<FILLED; i++)); do printf "#"; done
printf "${NC}"
for ((i=0; i<EMPTY; i++)); do printf "-"; done
printf "] %.1f%%\n\n" $PERCENT

# 警告信息
if [ $(echo "$REMAINING <= 0" | bc 2>/dev/null || echo "0") -eq 1 ]; then
    echo -e "${RED}❌ 流量已用尽！${NC}"
elif [ $(echo "$REMAINING < $CRITICAL_REMAINING_GB" | bc 2>/dev/null || echo "0") -eq 1 ]; then
    echo -e "${RED}⚠️  剩余流量不足 ${CRITICAL_REMAINING_GB}GB！${NC}"
elif [ $REMAINING_PERCENT -lt $WARNING_REMAINING_PERCENT ]; then
    echo -e "${YELLOW}⚠️  流量已使用超过 $((100 - WARNING_REMAINING_PERCENT))%！${NC}"
fi

echo ""

# 当前限速状态
echo "=========================================="
echo "        当前限速状态"
echo "=========================================="

# 检查 tc 规则
if tc qdisc show dev $INTERFACE 2>/dev/null | grep -q "htb\|tbf"; then
    RATE=$(tc class show dev $INTERFACE 2>/dev/null | grep "htb" | grep -o "rate [^ ]*" | head -1 | cut -d' ' -f2)
    if [ -z "$RATE" ]; then
        RATE=$(tc qdisc show dev $INTERFACE 2>/dev/null | grep "tbf" | grep -o "rate [^ ]*" | head -1 | cut -d' ' -f2)
    fi
    
    if [ -n "$RATE" ]; then
        echo -e "已启用限速: ${YELLOW}$RATE${NC}"
    else
        echo "已启用限速（无法获取速率）"
    fi
else
    echo -e "未启用限速 (${GREEN}正常${NC})"
fi

echo ""

# vnstat 原始数据
echo "=========================================="
echo "        vnstat 本月统计"
echo "=========================================="
vnstat -i $INTERFACE -m 2>/dev/null | head -10 || echo "无法获取 vnstat 数据"

echo ""

# 显示通知配置
echo "=========================================="
echo "        通知配置"
echo "=========================================="
if [ "$NOTIFY_ENABLED" = "true" ]; then
    echo "通知: 已启用"
    if [ -n "$NOTIFY_EMAIL" ]; then
        echo "  邮件: $NOTIFY_EMAIL"
    fi
    if [ -n "$NOTIFY_DINGTALK_WEBHOOK" ]; then
        echo "  钉钉: 已配置"
    fi
else
    echo "通知: 未启用"
fi

echo ""
