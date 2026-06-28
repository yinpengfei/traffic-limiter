#!/bin/bash

# ========================================
# 流量限制器 - 每日流量日报
# 每天定时发送钉钉日报（昨日用量 + 剩余流量）
# ========================================

CONFIG_FILE="/etc/traffic_limiter.conf"
[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"

# 默认值
INTERFACE="${INTERFACE:-eth0}"
TOTAL_LIMIT_GB="${TOTAL_LIMIT_GB:-1024}"
BASELINE_FILE="${BASELINE_FILE:-/var/lib/traffic_baseline}"
STATE_FILE="${STATE_FILE:-/var/lib/traffic_state}"
LOG_FILE="${LOG_FILE:-/var/log/traffic_limiter.log}"
NOTIFY_ENABLED="${NOTIFY_ENABLED:-false}"
NOTIFY_DINGTALK_WEBHOOK="${NOTIFY_DINGTALK_WEBHOOK:-}"
NOTIFY_DINGTALK_SECRET="${NOTIFY_DINGTALK_SECRET:-}"

# 每日用量记录文件（记录每天开始时的累计流量，用于计算昨日增量）
DAILY_SNAPSHOT_FILE="${DAILY_SNAPSHOT_FILE:-/var/lib/traffic_daily_snapshot}"

# ============ 日志 ============
log_message() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null
    echo "[$timestamp] [daily-report] $1" >> "$LOG_FILE"
}

# ============ 获取 vnstat 累计总流量 (GB) ============
get_total_traffic_gb() {
    local json
    json=$(vnstat -i "$INTERFACE" --json 2>/dev/null)
    [ -z "$json" ] && echo "0.000" && return
    local rx tx
    rx=$(echo "$json" | jq '.interfaces[0].traffic.total.rx' 2>/dev/null || echo "0")
    tx=$(echo "$json" | jq '.interfaces[0].traffic.total.tx' 2>/dev/null || echo "0")
    echo "scale=3; ($rx + $tx) / 1024 / 1024 / 1024" | bc
}

# ============ 获取当期已用流量 (GB) ============
get_period_used_gb() {
    local current_total baseline used offset
    current_total=$(get_total_traffic_gb)
    baseline=$(cat "$BASELINE_FILE" 2>/dev/null || echo "0")
    offset=$(cat "${USED_OFFSET_FILE:-/var/lib/traffic_used_offset}" 2>/dev/null || echo "0")
    if [ $(echo "$baseline == 0" | bc 2>/dev/null || echo "0") -eq 1 ]; then
        echo "$offset" && return
    fi
    used=$(echo "scale=3; $current_total - $baseline + $offset" | bc 2>/dev/null || echo "$offset")
    [ "$(echo "$used < 0" | bc 2>/dev/null)" = "1" ] && used="0.000"
    echo "$used"
}

# ============ 计算昨日使用量 ============
# 逻辑：今天运行时，读取"昨天记录的快照"，与"当前计费期已用"做差
# 快照格式：<日期YYYY-MM-DD> <累计总GB>
get_yesterday_used_gb() {
    local today yesterday snapshot_date snapshot_total current_total yesterday_used

    today=$(date +%Y-%m-%d)
    yesterday=$(date -d "yesterday" +%Y-%m-%d 2>/dev/null || date -v-1d +%Y-%m-%d 2>/dev/null || echo "")

    if [ ! -f "$DAILY_SNAPSHOT_FILE" ]; then
        # 第一次运行，保存今日快照，无昨日数据
        current_total=$(get_total_traffic_gb)
        echo "$today $current_total" > "$DAILY_SNAPSHOT_FILE"
        echo "N/A"
        return
    fi

    read -r snapshot_date snapshot_total < "$DAILY_SNAPSHOT_FILE"
    current_total=$(get_total_traffic_gb)

    if [ "$snapshot_date" = "$yesterday" ]; then
        # 快照是昨天的 -> 计算差值
        yesterday_used=$(echo "scale=3; $current_total - $snapshot_total" | bc 2>/dev/null || echo "0")
        [ "$(echo "$yesterday_used < 0" | bc 2>/dev/null)" = "1" ] && yesterday_used="0.000"
        echo "$yesterday_used"
    elif [ "$snapshot_date" = "$today" ]; then
        # 今天已经刷新过快照（说明 cron 重复触发），用 0 占位
        echo "0.000"
    else
        # 快照日期更早（服务器停机等情况），记录昨日增量为 N/A 并刷新
        current_total=$(get_total_traffic_gb)
        echo "$today $current_total" > "$DAILY_SNAPSHOT_FILE"
        echo "N/A"
        return
    fi

    # 刷新今日快照（不管之前是否存在）
    echo "$today $current_total" > "$DAILY_SNAPSHOT_FILE"
}

# ============ 生成进度条 ============
make_progress_bar() {
    local percent=$1
    local total=20
    local filled=$(echo "$percent * $total / 100" | bc 2>/dev/null || echo "0")
    [ "$filled" -gt "$total" ] 2>/dev/null && filled=$total
    local empty=$(( total - filled ))
    local bar=""
    local i
    for (( i=0; i<filled; i++ )); do bar="${bar}█"; done
    for (( i=0; i<empty; i++ )); do  bar="${bar}░"; done
    echo "$bar"
}

# ============ 钉钉加签 ============
dingtalk_get_signed_url() {
    local webhook="$1"
    local secret="$2"
    if [ -z "$secret" ]; then
        echo "$webhook"
        return
    fi
    local timestamp sign string_to_sign
    timestamp=$(date +%s%3N 2>/dev/null || echo "$(date +%s)000")
    string_to_sign=$(printf "%s\n%s" "$timestamp" "$secret")
    sign=$(printf "%s" "$string_to_sign" | openssl dgst -sha256 -hmac "$secret" -binary 2>/dev/null | base64 | tr -d '\n')
    sign=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$sign', safe=''))" 2>/dev/null || echo "$sign" | sed 's/+/%2B/g; s/\//%2F/g')
    echo "${webhook}&timestamp=${timestamp}&sign=${sign}"
}

# ============ 发送钉钉 Markdown 消息 ============
send_dingtalk_markdown() {
    local title="$1"
    local content="$2"

    if [ -z "$NOTIFY_DINGTALK_WEBHOOK" ]; then
        log_message "错误: 钉钉 Webhook 未配置"
        return 1
    fi

    # 将内容中的换行符转为 \n（JSON 安全）
    local escaped_content
    escaped_content=$(printf '%s' "$content" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || \
                      printf '%s' "$content" | sed 's/\\/\\\\/g; s/"/\\"/g' | awk '{printf "%s\\n", $0}' | sed 's/\\n$//')

    # 加签
    local signed_url
    signed_url=$(dingtalk_get_signed_url "$NOTIFY_DINGTALK_WEBHOOK" "$NOTIFY_DINGTALK_SECRET")

    curl -s -X POST "$signed_url" \
        -H "Content-Type: application/json" \
        -d "{
            \"msgtype\": \"markdown\",
            \"markdown\": {
                \"title\": \"$title\",
                \"text\": $escaped_content
            }
        }" 2>/dev/null
}

# ============ 主函数 ============
main() {
    log_message "===== 每日流量日报开始 ====="

    # 计算当期数据
    local period_used remaining_gb used_percent remaining_percent
    period_used=$(get_period_used_gb)
    remaining_gb=$(echo "scale=3; $TOTAL_LIMIT_GB - $period_used" | bc 2>/dev/null || echo "$TOTAL_LIMIT_GB")
    [ "$(echo "$remaining_gb < 0" | bc 2>/dev/null)" = "1" ] && remaining_gb="0.000"

    used_percent=$(echo "scale=1; $period_used / $TOTAL_LIMIT_GB * 100" | bc 2>/dev/null || echo "0")
    remaining_percent=$(echo "scale=1; 100 - $used_percent" | bc 2>/dev/null || echo "100")
    [ "$(echo "$remaining_percent < 0" | bc 2>/dev/null)" = "1" ] && remaining_percent="0.0"

    # 计算昨日用量
    local yesterday_used
    yesterday_used=$(get_yesterday_used_gb)

    # 进度条
    local percent_int
    percent_int=$(echo "$used_percent" | cut -d. -f1)
    [ -z "$percent_int" ] && percent_int=0
    local progress_bar
    progress_bar=$(make_progress_bar "$percent_int")

    # 限速状态
    local speed_status="正常"
    if command -v tc &>/dev/null; then
        if tc qdisc show dev "$INTERFACE" 2>/dev/null | grep -qE "htb|tbf"; then
            local current_rate
            current_rate=$(tc class show dev "$INTERFACE" 2>/dev/null | grep -o "rate [^ ]*" | head -1 | awk '{print $2}')
            [ -n "$current_rate" ] && speed_status="已限速 ($current_rate)" || speed_status="已限速"
        fi
    fi

    # 计费周期下次重置日期
    local reset_day today_d current_month next_reset
    reset_day="${RESET_DAY:-1}"
    today_d=$(date +%d | sed 's/^0*//')
    current_month=$(date +%Y-%m)
    if [ "$today_d" -ge "$reset_day" ]; then
        next_reset=$(date -d "${current_month}-${reset_day} +1 month" +%Y-%m-%d 2>/dev/null || \
                     date -v+1m -j -f "%Y-%m-%d" "${current_month}-$(printf '%02d' $reset_day)" +%Y-%m-%d 2>/dev/null || \
                     echo "待查询")
    else
        next_reset="${current_month}-$(printf '%02d' $reset_day)"
    fi

    # 状态 emoji
    local status_emoji="✅"
    local pct_int_val
    pct_int_val=$(echo "$percent_int" | sed 's/[^0-9]//g')
    [ "${pct_int_val:-0}" -ge 90 ] && status_emoji="🔴"
    [ "${pct_int_val:-0}" -ge 80 ] && [ "${pct_int_val:-0}" -lt 90 ] && status_emoji="🟡"

    local hostname_str
    hostname_str=$(hostname 2>/dev/null || echo "未知")
    local report_date
    report_date=$(date '+%Y-%m-%d %H:%M')

    # 构建 Markdown 消息内容
    local msg_content
    msg_content="## ${status_emoji} 流量日报 - ${report_date}

**主机**: ${hostname_str}  
**计费周期重置日**: 每月 ${reset_day} 号 | **下次重置**: ${next_reset}

---

### 📊 本计费周期用量

| 项目 | 数值 |
| :--- | :--- |
| 总流量限制 | **${TOTAL_LIMIT_GB} GB** |
| 已用流量 | **${period_used} GB** (${used_percent}%) |
| 剩余流量 | **${remaining_gb} GB** (${remaining_percent}%) |
| 昨日新增 | **${yesterday_used} GB** |
| 当前限速 | ${speed_status} |

**进度**: ${progress_bar} ${used_percent}%

---

> 流量监控系统自动发送，如需手动查询请运行 \`traffic_ctl status\`"

    log_message "已用: ${period_used}GB / ${TOTAL_LIMIT_GB}GB，昨日: ${yesterday_used}GB，剩余: ${remaining_gb}GB"

    # 发送钉钉
    if [ "$NOTIFY_ENABLED" = "true" ] && [ -n "$NOTIFY_DINGTALK_WEBHOOK" ]; then
        send_dingtalk_markdown "流量日报 - ${hostname_str}" "$msg_content"
        log_message "钉钉日报已发送"
    else
        log_message "通知未启用或 Webhook 未配置，跳过发送"
        # 打印到终端（便于手动测试）
        echo "==========================================="
        echo " 流量日报 (${report_date})"
        echo "==========================================="
        echo " 主机      : ${hostname_str}"
        echo " 总限制    : ${TOTAL_LIMIT_GB} GB"
        echo " 已用      : ${period_used} GB (${used_percent}%)"
        echo " 剩余      : ${remaining_gb} GB (${remaining_percent}%)"
        echo " 昨日新增  : ${yesterday_used} GB"
        echo " 限速状态  : ${speed_status}"
        echo " 进度      : [${progress_bar}] ${used_percent}%"
        echo " 下次重置  : ${next_reset}"
        echo "==========================================="
        echo ""
        echo "提示: 配置 NOTIFY_ENABLED=true 和 NOTIFY_DINGTALK_WEBHOOK 后可自动发送钉钉"
    fi

    log_message "===== 每日流量日报完成 ====="
}

mkdir -p "$(dirname "$LOG_FILE")" "$(dirname "$BASELINE_FILE")" "$(dirname "$DAILY_SNAPSHOT_FILE")" 2>/dev/null
main
