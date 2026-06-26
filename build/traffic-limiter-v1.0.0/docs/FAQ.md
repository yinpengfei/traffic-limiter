# 常见问题 FAQ

## 安装相关问题

### Q: 安装时提示"缺少依赖"怎么办？

**A:** 手动安装依赖：

```bash
# CentOS/RHEL
yum install -y vnstat jq bc iproute-tc

# Ubuntu/Debian
apt update && apt install -y vnstat jq bc iproute2
```

### Q: 安装时提示"网卡不存在"怎么办？

**A:** 先查看系统可用的网卡：

```bash
ip addr
```

或

```bash
ip -o link show
```

常见网卡名称：
- `eth0`, `eth1` (传统命名)
- `ens3`, `ens5` (PCI 网卡)
- `enp0s3`, `enp0s8` (基于硬件位置命名)

然后重新运行初始化：

```bash
traffic_limiter_init.sh
```

## 流量统计问题

### Q: 显示的流量和实际不符怎么办？

**A:** 可能是基准值设置不准确，使用以下方法校准：

```bash
# 方法1: 通过运营商后台的已用流量反推
# 假设运营商显示已用 500GB
traffic_ctl set-used 500

# 方法2: 如果刚续费，直接重置
traffic_ctl reset

# 方法3: 检查 vnstat 数据是否准确
vnstat -i eth0 --json | jq '.interfaces[0].traffic.total'
```

### Q: vnstat 数据不更新怎么办？

**A:** 

1. 检查 vnstat 服务状态：

```bash
systemctl status vnstat
```

2. 重启 vnstat 服务：

```bash
systemctl restart vnstat
```

3. 检查 vnstat 配置：

```bash
cat /etc/vnstat.conf | grep UpdateInterval
# 建议设置为 60 (秒)
```

4. 手动更新：

```bash
vnstat -i eth0 --update
```

### Q: 流量重置日不是每月1号，如何设置？

**A:** 在配置文件中设置 `RESET_DAY`：

```bash
traffic_ctl config edit

# 修改 RESET_DAY
RESET_DAY=15  # 每月 15 号重置
```

**注意**: 如果购买日是月底(29-31号)，建议设置为 28 号。

### Q: 首次购买不是整月，如何统计？

**A:** 安装完成后，手动设置已用流量：

```bash
# 假设运营商显示已用 300GB
traffic_ctl set-used 300
```

## 限速问题

### Q: 限速没有生效怎么办？

**A:** 

1. 检查 tc 规则是否应用：

```bash
tc qdisc show dev eth0
tc class show dev eth0
```

2. 检查是否触发了限速条件：

```bash
traffic_ctl status
```

3. 手动测试限速：

```bash
# 手动应用限速
traffic_ctl limit 10mbit

# 测试速度
wget -O /dev/null http://speedtest.tele2.net/10MB.zip
```

4. 检查配置文件：

```bash
traffic_ctl config
```

### Q: 限速后网速还是很慢怎么办？

**A:** 可能是限速速率设置过低，调整配置：

```bash
traffic_ctl config edit

# 提高限速速率
WARNING_RATE="20mbit"
CRITICAL_RATE="5mbit"
```

或者临时取消限速：

```bash
traffic_ctl unlimit
```

### Q: 如何让限速只对上传/下载生效？

**A:** 修改 `traffic_limiter.sh` 中的 `apply_tc_limit` 函数，分别设置上行和下行限速：

```bash
apply_tc_limit() {
    local rate=$1
    
    # 清除旧规则
    tc qdisc del dev $INTERFACE root 2>/dev/null
    
    # 创建队列
    tc qdisc add dev $INTERFACE root handle 1: htb
    
    # 创建根类（总带宽）
    tc class add dev $INTERFACE parent 1: classid 1:1 htb rate 100mbit
    
    # 创建子类（限速）
    tc class add dev $INTERFACE parent 1:1 classid 1:10 htb rate $rate ceil $rate
    
    # 应用过滤器（针对出站流量）
    tc filter add dev $INTERFACE protocol ip parent 1:0 prio 1 handle 10 fw classid 1:10
}
```

## 通知问题

### Q: 邮件通知没有收到怎么办？

**A:** 

1. 检查系统是否安装 mail 命令：

```bash
which mail
# 或
mail --version
```

2. 安装 mail 命令：

```bash
# CentOS
yum install -y mailx

# Ubuntu
apt install -y mailutils
```

3. 测试邮件发送：

```bash
echo "test" | mail -s "test" your@email.com
```

4. 检查配置文件：

```bash
traffic_ctl config

# 确保以下配置正确
NOTIFY_ENABLED=true
NOTIFY_EMAIL="your@email.com"
```

### Q: Webhook 通知如何配置？

**A:** 

1. 钉钉机器人：

```bash
# 创建钉钉机器人，获取 Webhook URL
NOTIFY_ENABLED=true
NOTIFY_WEBHOOK="https://oapi.dingtalk.com/robot/send?access_token=xxx"
```

2. 企业微信机器人：

```bash
# 创建企业微信群机器人，获取 Webhook URL
NOTIFY_ENABLED=true
NOTIFY_WEBHOOK="https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=xxx"
```

3. 自定义 Webhook（兼容 Slack 格式）：

```bash
NOTIFY_ENABLED=true
NOTIFY_WEBHOOK="https://your-webhook-url"
```

## 其他问题

### Q: 如何备份配置和数据？

**A:** 

```bash
# 备份配置文件
cp /etc/traffic_limiter.conf /backup/

# 备份基准值
cp /var/lib/traffic_baseline /backup/
cp /var/lib/traffic_state /backup/

# 备份 vnstat 数据
cp /var/lib/vnstat/* /backup/vnstat/
```

### Q: 如何迁移到新服务器？

**A:** 

1. 在原服务器备份：

```bash
tar -czvf traffic_limiter_backup.tar.gz \
    /etc/traffic_limiter.conf \
    /var/lib/traffic_baseline \
    /var/lib/traffic_state \
    /var/lib/vnstat/
```

2. 在新服务器恢复：

```bash
# 安装流量限制器
./install.sh

# 恢复配置和数据
cp traffic_limiter.conf /etc/
cp traffic_baseline /var/lib/
cp traffic_state /var/lib/
cp vnstat_backup/* /var/lib/vnstat/

# 重启服务
systemctl restart vnstat
```

### Q: 如何完全卸载？

**A:** 

```bash
cd traffic-limiter
./uninstall.sh
```

或手动卸载：

```bash
# 停止服务
systemctl stop traffic-limiter-restore.service
systemctl disable traffic-limiter-restore.service

# 删除文件
rm -f /usr/local/bin/traffic_limiter.sh
rm -f /usr/local/bin/traffic_query.sh
rm -f /usr/local/bin/traffic_ctl
rm -f /usr/local/bin/traffic_limiter_init.sh
rm -f /etc/traffic_limiter.conf
rm -f /etc/systemd/system/traffic-limiter-restore.service

# 删除定时任务
crontab -e
# 删除包含 traffic_limiter 的行

# 清除限速规则
tc qdisc del dev eth0 root
```
