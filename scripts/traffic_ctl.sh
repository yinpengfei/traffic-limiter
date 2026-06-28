#!/bin/bash

# ========================================
# 流量限制器 - 管理工具
# 用法: traffic_ctl <命令> [参数]
# ========================================

CONFIG_FILE="/etc/traffic_limiter.conf"

# 加载配置
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
USED_OFFSET_FILE="${USED_OFFSET_FILE:-/var/lib/traffic_used_offset}"
LOG_FILE="${LOG_FILE:-/var/log/traffic_limiter.log}"

case "$1" in
    status)
        # 查看状态
        bash /usr/local/bin/traffic_query.sh
        ;;
    
    set-used)
        # 设置已用流量（通过偏移量校准历史流量）
        # traffic_ctl set-used 175.20
        if [ -z "$2" ]; then
            echo "用法: traffic_ctl set-used <已用GB>"
            echo "示例: traffic_ctl set-used 175.20"
            echo "说明: 用于校准部署前的历史流量，设置后 vnstat 统计+偏移量=实际已用"
            exit 1
        fi
        
        DESIRED_USED=$2
        CURRENT=$(vnstat -i $INTERFACE --json 2>/dev/null | jq '.interfaces[0].traffic.total.rx + .interfaces[0].traffic.total.tx' 2>/dev/null | awk '{printf "%.3f", $1/1024/1024/1024}')
        if [ -z "$CURRENT" ]; then
            echo "错误: 无法获取 vnstat 数据"
            exit 1
        fi
        
        BASELINE=$(cat $BASELINE_FILE 2>/dev/null || echo "0")
        VNSTAT_USED=$(echo "scale=3; $CURRENT - $BASELINE" | bc)
        OFFSET=$(echo "scale=3; $DESIRED_USED - $VNSTAT_USED" | bc)
        if [ $(echo "$OFFSET < 0" | bc 2>/dev/null || echo "0") -eq 1 ]; then
            echo "警告: 计算的偏移量为负（${OFFSET}），设为 0"
            echo "说明: 期望值小于 vnstat 已统计值，无需偏移"
            OFFSET=0
        fi
        
        echo "$OFFSET" > $USED_OFFSET_FILE
        echo "✓ 已校准已用流量: ${DESIRED_USED}GB"
        echo "  vnstat 已统计: ${VNSTAT_USED}GB"
        echo "  偏移量: ${OFFSET}GB"
        echo "  计算公式: ${VNSTAT_USED} + ${OFFSET} = $(echo "scale=3; $VNSTAT_USED + $OFFSET" | bc)GB"
        ;;
    
    set-baseline)
        # 直接设置基准值: traffic_ctl set-baseline 1000
        if [ -z "$2" ]; then
            echo "用法: traffic_ctl set-baseline <基准值GB>"
            echo "示例: traffic_ctl set-baseline 1000"
            exit 1
        fi
        
        echo "$2" > $BASELINE_FILE
        echo "✓ 已设置基准值: ${2}GB"
        ;;
    
    reset)
        # 手动重置（立即生效）: traffic_ctl reset
        CURRENT=$(vnstat -i $INTERFACE --json 2>/dev/null | jq '.interfaces[0].traffic.total.rx + .interfaces[0].traffic.total.tx' 2>/dev/null | awk '{printf "%.3f", $1/1024/1024/1024}')
        if [ -z "$CURRENT" ]; then
            CURRENT=0
        fi
        
        echo "$CURRENT" > $BASELINE_FILE
        echo "0" > $USED_OFFSET_FILE
        echo "LAST_RESET=$(date +%Y-%m)" > $STATE_FILE
        echo "LAST_RESET_TIMESTAMP=$(date +%s)" >> $STATE_FILE
        
        tc qdisc del dev $INTERFACE root 2>/dev/null
        echo "✓ 已手动重置流量统计"
        echo "  基准值: ${CURRENT}GB"
        echo "  偏移量: 已清零"
        echo "  重置时间: $(date '+%Y-%m-%d %H:%M:%S')"
        ;;
    
    limit)
        # 手动限速: traffic_ctl limit 10mbit
        if [ -z "$2" ]; then
            echo "用法: traffic_ctl limit <速率>"
            echo "示例: traffic_ctl limit 10mbit"
            echo "常见速率: 10mbit, 5mbit, 1mbit, 500kbit"
            exit 1
        fi
        
        # 清除旧规则
        tc qdisc del dev $INTERFACE root 2>/dev/null
        
        # 尝试 htb
        if tc qdisc add dev $INTERFACE root handle 1: htb default 10 2>/dev/null; then
            if tc class add dev $INTERFACE parent 1: classid 1:10 htb rate $2 ceil $2 2>/dev/null; then
                echo "✓ 已手动设置限速 (htb): $2"
                exit 0
            fi
        fi
        
        # Fallback to tbf
        if tc qdisc add dev $INTERFACE root tbf rate $2 burst 32kbit latency 400ms 2>/dev/null; then
            echo "✓ 已手动设置限速 (tbf): $2"
            exit 0
        fi
        
        echo "错误: 无法应用限速规则"
        exit 1
        ;;
    
    unlimit)
        # 取消限速: traffic_ctl unlimit
        tc qdisc del dev $INTERFACE root 2>/dev/null
        echo "✓ 已取消限速"
        ;;
    
    config)
        # 配置管理: traffic_ctl config [edit|show]
        case "$2" in
            edit)
                ${EDITOR:-vi} $CONFIG_FILE
                ;;
            show)
                echo "当前配置:"
                echo "=========================================="
                cat $CONFIG_FILE
                echo "=========================================="
                ;;
            *)
                echo "用法: traffic_ctl config [edit|show]"
                echo "  edit - 编辑配置文件"
                echo "  show - 显示当前配置"
                ;;
        esac
        ;;
    
    notify)
        # 发送测试通知: traffic_ctl notify "测试消息"
        if [ -z "$2" ]; then
            echo "用法: traffic_ctl notify <消息>"
            echo "示例: traffic_ctl notify \"测试消息\""
            exit 1
        fi
        
        if [ "$NOTIFY_ENABLED" != "true" ]; then
            echo "警告: 通知未启用，请在配置文件中设置 NOTIFY_ENABLED=true"
        fi
        
        # 发送通知
        if [ -n "$NOTIFY_EMAIL" ]; then
            echo "$2" | mail -s "流量限制器 - 测试通知" $NOTIFY_EMAIL 2>/dev/null
            echo "✓ 邮件通知已发送: $NOTIFY_EMAIL"
        fi
        
        if [ -n "$NOTIFY_DINGTALK_WEBHOOK" ]; then
            # 发送钉钉消息
            curl -s -X POST "$NOTIFY_DINGTALK_WEBHOOK" \
                -H "Content-Type: application/json" \
                -d "{
                    \"msgtype\": \"text\",
                    \"text\": {
                        \"content\": \"$2\"
                    }
                }" 2>/dev/null
            echo "✓ 钉钉通知已发送"
        fi
        ;;
    
    log)
        # 查看日志: traffic_ctl log [行数]
        LINES=${2:-50}
        if [ -f "$LOG_FILE" ]; then
            tail -n $LINES "$LOG_FILE"
        else
            echo "日志文件不存在: $LOG_FILE"
        fi
        ;;
    
    report)
        # 立即发送流量日报: traffic_ctl report
        echo "正在生成并发送流量日报..."
        bash /usr/local/bin/traffic_daily_report.sh
        ;;

    report-time)
        # 查看或修改日报发送时间: traffic_ctl report-time [HH:MM]
        if [ -z "$2" ]; then
            # 显示当前 crontab 中的日报任务
            echo "当前日报 crontab 设置:"
            crontab -l 2>/dev/null | grep "traffic_daily_report" || echo "  (未设置)"
            echo ""
            echo "配置中的时间:"
            local hour="${DAILY_REPORT_HOUR:-1}"
            local minute="${DAILY_REPORT_MINUTE:-0}"
            printf "  每天 %02d:%02d\n" "$hour" "$minute"
            echo ""
            echo "提示: 使用 traffic_ctl report-time HH:MM 修改时间"
        else
            # 解析 HH:MM
            local new_hour new_minute
            new_hour=$(echo "$2" | cut -d: -f1 | sed 's/^0*//')
            new_minute=$(echo "$2" | cut -d: -f2 | sed 's/^0*//')
            [ -z "$new_hour" ]   && new_hour=0
            [ -z "$new_minute" ] && new_minute=0

            if [ "$new_hour" -lt 0 ] || [ "$new_hour" -gt 23 ] || \
               [ "$new_minute" -lt 0 ] || [ "$new_minute" -gt 59 ]; then
                echo "错误: 无效的时间格式，请使用 HH:MM（例如 01:00、08:30）"
                exit 1
            fi

            # 更新 crontab：先删除旧日报任务，再添加新的
            (crontab -l 2>/dev/null | grep -v "traffic_daily_report") | crontab -
            (crontab -l 2>/dev/null; echo "$new_minute $new_hour * * * /usr/local/bin/traffic_daily_report.sh >> /var/log/traffic_limiter.log 2>&1") | crontab -

            # 更新配置文件中的时间
            if [ -f "$CONFIG_FILE" ]; then
                sed -i "s/^DAILY_REPORT_HOUR=.*/DAILY_REPORT_HOUR=$new_hour/" "$CONFIG_FILE"
                sed -i "s/^DAILY_REPORT_MINUTE=.*/DAILY_REPORT_MINUTE=$new_minute/" "$CONFIG_FILE"
                # 如果配置项不存在则追加
                grep -q "^DAILY_REPORT_HOUR=" "$CONFIG_FILE" || echo "DAILY_REPORT_HOUR=$new_hour" >> "$CONFIG_FILE"
                grep -q "^DAILY_REPORT_MINUTE=" "$CONFIG_FILE" || echo "DAILY_REPORT_MINUTE=$new_minute" >> "$CONFIG_FILE"
            fi

            printf "✓ 日报时间已更新为每天 %02d:%02d\n" "$new_hour" "$new_minute"
            echo "  crontab: $new_minute $new_hour * * * /usr/local/bin/traffic_daily_report.sh"
        fi
        ;;

    dingtalk)
        # 钉钉配置向导: traffic_ctl dingtalk
        echo "=========================================="
        echo "      钉钉通知配置向导"
        echo "=========================================="
        echo ""
        echo "步骤:"
        echo "  1. 在钉钉群中点击 '群设置' -> '机器人'"
        echo "  2. 点击 '添加机器人' -> '自定义'"
        echo "  3. 设置机器人名称和图标"
        echo "  4. 复制 Webhook 地址"
        echo ""
        read -p "请输入钉钉 Webhook 地址: " WEBHOOK
        
        if [ -z "$WEBHOOK" ]; then
            echo "取消配置"
            exit 0
        fi
        
        # 更新配置文件
        if grep -q "NOTIFY_DINGTALK_WEBHOOK" $CONFIG_FILE; then
            sed -i "s|NOTIFY_DINGTALK_WEBHOOK=.*|NOTIFY_DINGTALK_WEBHOOK=\"$WEBHOOK\"|" $CONFIG_FILE
        else
            echo "" >> $CONFIG_FILE
            echo "# 钉钉 Webhook" >> $CONFIG_FILE
            echo "NOTIFY_DINGTALK_WEBHOOK=\"$WEBHOOK\"" >> $CONFIG_FILE
        fi
        
        # 启用通知
        sed -i "s|NOTIFY_ENABLED=.*|NOTIFY_ENABLED=true|" $CONFIG_FILE
        
        echo ""
        echo "✓ 钉钉通知已配置"
        echo ""
        read -p "是否发送测试消息? (y/n): " TEST
        if [ "$TEST" = "y" ]; then
            bash $0 notify "流量限制器 - 钉钉通知测试成功！"
        fi
        ;;
    
    *)
        echo "流量限制器管理工具"
        echo ""
        echo "用法: traffic_ctl <命令> [参数]"
        echo ""
        echo "命令:"
        echo "  status              查看流量使用情况和限速状态"
        echo "  set-used <GB>       设置已用流量（校准用）"
        echo "  set-baseline <GB>   直接设置基准值"
        echo "  reset               手动重置流量统计"
        echo "  limit <速率>        手动限速"
        echo "  unlimit             取消限速"
        echo "  config [edit|show]  查看/编辑配置"
        echo "  notify <消息>       发送测试通知"
        echo "  report              立即发送流量日报"
        echo "  report-time [HH:MM] 查看或修改日报发送时间"
        echo "  dingtalk            配置钉钉通知"
        echo "  log [行数]          查看日志（默认 50 行）"
        echo ""
        echo "示例:"
        echo "  traffic_ctl status"
        echo "  traffic_ctl set-used 500"
        echo "  traffic_ctl limit 10mbit"
        echo "  traffic_ctl dingtalk"
        echo ""
        exit 1
        ;;
esac
