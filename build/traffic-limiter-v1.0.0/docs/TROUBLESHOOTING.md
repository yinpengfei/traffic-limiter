# 故障排查指南

## 日志查看

### 查看主日志

```bash
traffic_ctl log 100
# 或
tail -f /var/log/traffic_limiter.log
```

### 查看系统日志

```bash
journalctl -u traffic-limiter-restore.service -f
```

### 查看 vnstat 日志

```bash
journalctl -u vnstat -f
```

## 常见问题排查

### 1. 脚本不执行

**症状**: 定时任务没有执行，日志没有更新

**排查步骤**:

1. 检查 crontab 是否设置：

```bash
crontab -l | grep traffic_limiter
```

如果没有输出，重新设置：

```bash
(crontab -l 2>/dev/null; echo "*/10 * * * * /usr/local/bin/traffic_limiter.sh >> /var/log/traffic_limiter.log 2>&1") | crontab -
```

2. 检查脚本权限：

```bash
ls -l /usr/local/bin/traffic_limiter.sh
# 应该显示 -rwxr-xr-x
```

如果没有执行权限：

```bash
chmod +x /usr/local/bin/traffic_limiter.sh
```

3. 手动执行测试：

```bash
bash -x /usr/local/bin/traffic_limiter.sh
```

### 2. 流量统计不准确

**症状**: 显示的流量与运营商后台不符

**排查步骤**:

1. 检查 vnstat 数据：

```bash
vnstat -i eth0 --json | jq '.interfaces[0].traffic.total'
```

2. 检查基准值：

```bash
cat /var/lib/traffic_baseline
```

3. 重新校准：

```bash
# 假设运营商显示已用 500GB
traffic_ctl set-used 500
```

### 3. 限速规则不生效

**症状**: 已经触发限速条件，但网速没有变化

**排查步骤**:

1. 检查 tc 规则：

```bash
tc qdisc show dev eth0
tc class show dev eth0
```

2. 检查网卡名称：

```bash
ip addr
```

确保配置文件中的 `INTERFACE` 正确。

3. 手动应用限速测试：

```bash
tc qdisc add dev eth0 root handle 1: htb default 10
tc class add dev eth0 parent 1: classid 1:10 htb rate 10mbit ceil 10mbit
```

如果报错，可能是内核不支持 htb 队列。

4. 尝试使用 tbf 队列：

修改 `traffic_limiter.sh` 中的 `apply_tc_limit` 函数：

```bash
apply_tc_limit() {
    local rate=$1
    tc qdisc del dev $INTERFACE root 2>/dev/null
    tc qdisc add dev $INTERFACE root tbf rate $rate burst 32kbit latency 400ms
}
```

### 4. 系统重启后限速规则丢失

**症状**: 重启后限速规则消失

**原因**: tc 规则不会持久化，重启后会丢失

**解决方法**: 

确保 systemd 服务已启用：

```bash
systemctl status traffic-limiter-restore.service
```

如果没有启用：

```bash
systemctl enable traffic-limiter-restore.service
systemctl start traffic-limiter-restore.service
```

### 5. vnstat 数据丢失

**症状**: vnstat 显示的流量突然变为 0 或不准确

**原因**: 

- vnstat 数据库损坏
- 系统时间不正确
- 网卡名称变化

**解决方法**:

1. 备份并重建 vnstat 数据库：

```bash
# 备份
cp -r /var/lib/vnstat /var/lib/vnstat_backup

# 删除旧数据库
rm -f /var/lib/vnstat/*

# 重启 vnstat
systemctl restart vnstat

# 等待 5 分钟让数据重新收集
sleep 300

# 检查数据
vnstat -i eth0
```

2. 检查系统时间：

```bash
date
# 如果不准确，同步时间
ntpdate pool.ntp.org
# 或
timedatectl set-ntp true
```

3. 如果网卡名称变化，更新配置：

```bash
traffic_ctl config edit
# 修改 INTERFACE
```

### 6. 脚本执行报错

**常见错误和解决方法**:

#### 错误: `command not found: jq`

```bash
# 安装 jq
yum install -y jq  # CentOS
apt install -y jq  # Ubuntu
```

#### 错误: `command not found: bc`

```bash
# 安装 bc
yum install -y bc  # CentOS
apt install -y bc  # Ubuntu
```

#### 错误: `Can't parse JSON`

```bash
# vnstat 版本过低，不支持 --json 参数
# 升级 vnstat 到 2.0 以上
yum install -y epel-release
yum update -y vnstat
```

#### 错误: `RTNETLINK answers: Operation not supported`

```bash
# 内核不支持 htb，使用 tbf 队列
# 修改 traffic_limiter.sh 使用 tbf 而不是 htb
```

### 7. 性能问题

**症状**: 脚本执行很慢，或系统负载高

**排查**:

1. 检查 vnstat 更新频率：

```bash
cat /etc/vnstat.conf | grep UpdateInterval
# 建议设置为 60 或更高
```

2. 减少检查频率：

```bash
crontab -e
# 改为每 30 分钟检查一次
*/30 * * * * /usr/local/bin/traffic_limiter.sh
```

## 调试模式

### 启用详细日志

修改 `traffic_limiter.sh`，在开头添加：

```bash
set -x  # 启用调试模式
```

### 手动逐步执行

```bash
# 1. 加载配置
source /etc/traffic_limiter.conf

# 2. 检查依赖
which vnstat jq bc ip tc

# 3. 获取流量数据
vnstat -i $INTERFACE --json

# 4. 计算用量
cat /var/lib/traffic_baseline
echo "scale=3; $(vnstat -i $INTERFACE --json | jq '.interfaces[0].traffic.total.rx + .interfaces[0].traffic.total.tx') / 1024 / 1024 / 1024" | bc

# 5. 应用限速
tc qdisc add dev $INTERFACE root handle 1: htb default 10
tc class add dev $INTERFACE parent 1: classid 1:10 htb rate 10mbit ceil 10mbit
```

## 收集调试信息

如果问题无法解决，收集以下信息后提交 Issue：

```bash
# 创建调试信息文件
DEBUG_FILE="/tmp/traffic_limiter_debug.txt"

echo "=== 系统信息 ===" > $DEBUG_FILE
uname -a >> $DEBUG_FILE
cat /etc/os-release >> $DEBUG_FILE

echo -e "\n=== 网络信息 ===" >> $DEBUG_FILE
ip addr >> $DEBUG_FILE

echo -e "\n=== 配置文件 ===" >> $DEBUG_FILE
cat /etc/traffic_limiter.conf >> $DEBUG_FILE

echo -e "\n=== 基准值 ===" >> $DEBUG_FILE
cat /var/lib/traffic_baseline >> $DEBUG_FILE
cat /var/lib/traffic_state >> $DEBUG_FILE

echo -e "\n=== vnstat 信息 ===" >> $DEBUG_FILE
vnstat -i eth0 -m >> $DEBUG_FILE
vnstat -i eth0 --json >> $DEBUG_FILE

echo -e "\n=== tc 规则 ===" >> $DEBUG_FILE
tc qdisc show dev eth0 >> $DEBUG_FILE
tc class show dev eth0 >> $DEBUG_FILE

echo -e "\n=== 日志 ===" >> $DEBUG_FILE
tail -50 /var/log/traffic_limiter.log >> $DEBUG_FILE

echo -e "\n调试信息已保存到: $DEBUG_FILE"
```

## 获取帮助

如果以上方法都无法解决问题，请：

1. 查看文档: `docs/` 目录
2. 提交 Issue: [项目地址]/issues
3. 联系作者: [联系方式]
