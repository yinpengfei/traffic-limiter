#!/bin/bash

# ========================================
# 流量限制器 - 主程序
# ========================================

CONFIG_FILE="/etc/traffic_limiter.conf"
[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"

# 默认值
INTERFACE="${INTERFACE:-eth0}"
TOTAL_LIMIT_GB="${TOTAL_LIMIT_GB:-1024}"
RESET_DAY="${RESET_DAY:-1}"
WARNING_REMAINING_PERCENT="${WARNING_REMAINING_PERCENT:-10}"
CRITICAL_REMAINING_GB="${CRITICAL_REMAINING_GB:-10}"
WARNING_RATE="${WARNING_RATE:-10mbit}"
CRITICAL_RATE="${CRITICAL_RATE:-500kbit}"
BASELINE_FILE="${BASELINE_FILE:-/var/lib/traffic_baseline}"
STATE_FILE="${STATE_FILE:-/var/lib/traffic_state}"
USED_OFFSET_FILE="${USED_OFFSET_FILE:-/var/lib/traffic_used_offset}"
LOG_FILE="${LOG_FILE:-/var/log/traffic_limiter.log}"
NOTIFY_ENABLED="${NOTIFY_ENABLED:-false}"
NOTIFY_EMAIL="${NOTIFY_EMAIL:-}"
NOTIFY_DINGTALK_WEBHOOK="${NOTIFY_DINGTALK_WEBHOOK:-}"
NOTIFY_DINGTALK_SECRET="${NOTIFY_DINGTALK_SECRET:-}"

# 日志函数
log_message() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    mkdir -p $(dirname $LOG_FILE) 2>/dev/null
    echo "[$timestamp] $1" >> $LOG_FILE
    echo "[$timestamp] $1"
}

# 依赖检查
check_dependencies() {
    for cmd in vnstat jq bc ip tc; do
        command -v $cmd &>/dev/null || log_message "警告: 缺少 $cmd"
    done
}

# 网卡检查
check_interface() {
    ip link show $INTERFACE &>/dev/null || { log_message "错误: 网卡 $INTERFACE 不存在"; exit 1; }
}

# 获取总流量(GB)
get_total_traffic_gb() {
    local json=$(vnstat -i $INTERFACE --json 2>/dev/null)
    [ -z "$json" ] && echo "0.000" && return
    local rx=$(echo "$json" | jq '.interfaces[0].traffic.total.rx' 2>/dev/null || echo "0")
    local tx=$(echo "$json" | jq '.interfaces[0].traffic.total.tx' 2>/dev/null || echo "0")
    echo "scale=3; ($rx + $tx) / 1024 / 1024 / 1024" | bc
}

# 重置检查
check_reset() {
    local today=$(date +%d | sed 's/^0*//')
    local current_month=$(date +%Y-%m)
    local last_reset=""
    [ -f "$STATE_FILE" ] && last_reset=$(grep "^LAST_RESET=" "$STATE_FILE" 2>/dev/null | cut -d= -f2)
    
    local need_reset=0
    if [ "$today" -eq "$RESET_DAY" ] && [ "$last_reset" != "$current_month" ]; then
        need_reset=1
    fi
    
    if [ $need_reset -eq 1 ]; then
        log_message "执行流量重置"
        local current_total=$(get_total_traffic_gb)
        echo "$current_total" > "$BASELINE_FILE"
        echo "LAST_RESET=$current_month" > "$STATE_FILE"
        echo "LAST_RESET_TIMESTAMP=$(date +%s)" >> "$STATE_FILE"
        echo "0" > "$USED_OFFSET_FILE"
        tc qdisc del dev $INTERFACE root 2>/dev/null
        log_message "流量已重置，取消限速"
        notify "流量已重置，开始新的计费周期"
    fi
}

# 应用限速
apply_tc_limit() {
    local rate=$1
    tc qdisc del dev $INTERFACE root 2>/dev/null
    if tc qdisc add dev $INTERFACE root handle 1: htb default 10 2>/dev/null; then
        tc class add dev $INTERFACE parent 1: classid 1:10 htb rate $rate ceil $rate 2>/dev/null && return 0
    fi
    tc qdisc add dev $INTERFACE root tbf rate $rate burst 32kbit latency 400ms 2>/dev/null && return 0
    log_message "错误: 无法应用限速"
    return 1
}

# 钉钉加签：返回带 timestamp&sign 的完整 URL
# 钉钉签名算法: timestamp + "\n" + secret → HMAC-SHA256 → Base64 → URL Encode
dingtalk_get_signed_url() {
    local webhook="$1"
    local secret="$2"
    if [ -z "$secret" ]; then
        echo "$webhook"
        return
    fi
    local timestamp sign string_to_sign
    # 毫秒级时间戳（date +%s%3N 可能失败，fallback 到 +%s000）
    timestamp=$(date +%s%3N 2>/dev/null || echo "$(date +%s)000")
    string_to_sign=$(printf "%s\n%s" "$timestamp" "$secret")
    # HMAC-SHA256 → Base64
    sign=$(printf "%s" "$string_to_sign" | openssl dgst -sha256 -hmac "$secret" -binary 2>/dev/null | base64 | tr -d '\n')
    # URL Encode（用 python3，大多数云主机已预装）
    sign=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$sign', safe=''))" 2>/dev/null || echo "$sign" | sed 's/+/%2B/g; s/\//%2F/g')
    echo "${webhook}&timestamp=${timestamp}&sign=${sign}"
}

# 通知
notify() {
    local msg="$1"
    logger "Traffic Limiter: $msg" 2>/dev/null
    [ "$NOTIFY_ENABLED" != "true" ] && return
    
    [ -n "$NOTIFY_EMAIL" ] && echo "$msg" | mail -s "流量告警 - $(hostname)" $NOTIFY_EMAIL 2>/dev/null
    
    if [ -n "$NOTIFY_DINGTALK_WEBHOOK" ]; then
        local signed_url
        signed_url=$(dingtalk_get_signed_url "$NOTIFY_DINGTALK_WEBHOOK" "$NOTIFY_DINGTALK_SECRET")
        curl -s -X POST "$signed_url" \
            -H "Content-Type: application/json" \
            -d "{\"msgtype\":\"text\",\"text\":{\"content\":\"$msg\"}}" 2>/dev/null
    fi
}

# 主逻辑
main() {
    log_message "========== 流量限制器启动 =========="
    check_dependencies
    check_interface
    check_reset
    
    local current_total=$(get_total_traffic_gb)
    local baseline=$(cat $BASELINE_FILE 2>/dev/null || echo "0")
    [ $(echo "$baseline == 0" | bc 2>/dev/null || echo "0") -eq 1 ] && echo "$current_total" > $BASELINE_FILE && baseline=$current_total
    
    local offset=$(cat "$USED_OFFSET_FILE" 2>/dev/null || echo "0")
    local used=$(echo "scale=3; $current_total - $baseline + $offset" | bc)
    [ $(echo "$used < 0" | bc 2>/dev/null || echo "1") -eq 1 ] && used=0
    
    local remaining_gb=$(echo "scale=3; $TOTAL_LIMIT_GB - $used" | bc)
    [ $(echo "$remaining_gb < 0" | bc 2>/dev/null || echo "0") -eq 1 ] && remaining_gb=0
    
    local used_percent=$(echo "scale=2; $used / $TOTAL_LIMIT_GB * 100" | bc 2>/dev/null || echo "0")
    local remaining_percent=$(echo "scale=0; 100 - $used_percent" | bc 2>/dev/null | cut -d. -f1 || echo "100")
    [ -z "$remaining_percent" ] && remaining_percent=100
    [ $remaining_percent -lt 0 ] && remaining_percent=0
    
    log_message "已用: ${used}GB / ${TOTAL_LIMIT_GB}GB (${used_percent}%)"
    log_message "剩余: ${remaining_gb}GB (${remaining_percent}%)"
    
    # 限速判断（优先级：用尽 > 严格 > 警告）
    if [ $(echo "$remaining_gb <= 0" | bc 2>/dev/null || echo "0") -eq 1 ]; then
        # 流量已用尽
        apply_tc_limit $CRITICAL_RATE
        notify "❌ 流量已用尽！已限制到 ${CRITICAL_RATE}"
    elif [ $(echo "$remaining_gb < $CRITICAL_REMAINING_GB" | bc 2>/dev/null || echo "0") -eq 1 ]; then
        # 剩余不足 CRITICAL_REMAINING_GB
        apply_tc_limit $CRITICAL_RATE
        notify "⚠️ 剩余流量不足 ${CRITICAL_REMAINING_GB}GB！已限制到 ${CRITICAL_RATE}"
    elif [ $remaining_percent -le $WARNING_REMAINING_PERCENT ]; then
        # 剩余百分比不足 WARNING_REMAINING_PERCENT
        apply_tc_limit $WARNING_RATE
        notify "⚠️ 剩余流量不足 ${WARNING_REMAINING_PERCENT}%！已限制到 ${WARNING_RATE}"
    else
        # 流量充足，取消限速
        tc qdisc del dev $INTERFACE root 2>/dev/null
        log_message "✅ 流量充足，取消限速"
    fi
    
    log_message "========== 流量限制器完成 =========="
}

mkdir -p $(dirname $LOG_FILE) $(dirname $BASELINE_FILE) $(dirname $STATE_FILE) 2>/dev/null
main
