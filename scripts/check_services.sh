#!/bin/bash
# 服务健康检查脚本
# 检查系统中的关键服务状态

LOG_DIR="/media/lz/baba/monitor/logs"
CONFIG_DIR="/media/lz/baba/monitor/config"
SCRIPT_DIR="/media/lz/baba/monitor/scripts"

# 确保日志目录存在
mkdir -p "$LOG_DIR"

# 定义需要监控的服务列表
SERVICES=(
    "llama-server"
    "local-agent"
    "local_agent_mcp"
)

# 定义需要监控的端口
PORTS=(
    "8080"
    "7860"
)

# 检查服务状态
check_service() {
    local service_name=$1
    local status=$(systemctl is-active "$service_name" 2>/dev/null)
    
    if [ "$status" = "active" ]; then
        echo "OK: 服务 $service_name 运行正常"
        return 0
    elif [ "$status" = "inactive" ]; then
        echo "ERROR: 服务 $service_name 已停止"
        return 1
    elif [ "$status" = "failed" ]; then
        echo "ERROR: 服务 $service_name 运行失败"
        return 1
    else
        echo "WARNING: 服务 $service_name 状态未知或未安装"
        return 2
    fi
}

# 检查端口状态
check_port() {
    local port=$1
    local host="127.0.0.1"
    
    if timeout 2 bash -c "echo > /dev/tcp/$host/$port" 2>/dev/null; then
        echo "OK: 端口 $port 监听正常"
        return 0
    else
        echo "ERROR: 端口 $port 未监听"
        return 1
    fi
}

# 检查进程状态
check_process() {
    local process_name=$1
    local count=$(ps aux | grep -v grep | grep -c "$process_name")
    
    if [ "$count" -gt 0 ]; then
        echo "OK: 进程 $process_name 运行中 (数量: $count)"
        return 0
    else
        echo "ERROR: 进程 $process_name 未运行"
        return 1
    fi
}

# 主检查函数
main() {
    local all_ok=0
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "=========================================="
    echo "服务健康检查 - $timestamp"
    echo "=========================================="
    
    # 检查系统服务
    echo ""
    echo "[系统服务状态]"
    for service in "${SERVICES[@]}"; do
        check_service "$service"
        if [ $? -ne 0 ]; then
            all_ok=1
        fi
    done
    
    # 检查端口
    echo ""
    echo "[端口监听状态]"
    for port in "${PORTS[@]}"; do
        check_port "$port"
        if [ $? -ne 0 ]; then
            all_ok=1
        fi
    done
    
    # 检查关键进程
    echo ""
    echo "[关键进程状态]"
    check_process "llama-server"
    if [ $? -ne 0 ]; then
        all_ok=1
    fi
    
    check_process "local_agent"
    if [ $? -ne 0 ]; then
        all_ok=1
    fi
    
    # 检查网络状态
    echo ""
    echo "[网络状态]"
    if ping -c 1 -W 2 8.8.8.8 > /dev/null 2>&1; then
        echo "OK: 网络连接正常"
    else
        echo "ERROR: 网络连接异常"
        all_ok=1
    fi
    
    # 检查磁盘空间
    echo ""
    echo "[磁盘空间状态]"
    local disk_usage=$(df -h / | tail -1 | awk '{print $5}' | sed 's/%//')
    if [ "$disk_usage" -lt 90 ]; then
        echo "OK: 磁盘使用正常 (使用率: ${disk_usage}%)"
    else
        echo "WARNING: 磁盘空间不足 (使用率: ${disk_usage}%)"
        all_ok=1
    fi
    
    # 检查内存使用（兼容中英文输出）
    echo ""
    echo "[内存使用状态]"
    local mem_info=$(free -m | grep -E "^(Mem|内存)" | head -n 1)
    local mem_total=$(echo "$mem_info" | awk '{print $2}')
    local mem_used=$(echo "$mem_info" | awk '{print $3}')
    
    if [ -n "$mem_total" ] && [ "$mem_total" -gt 0 ]; then
        local mem_usage_percent=$((mem_used * 100 / mem_total))
        if [ "$mem_usage_percent" -lt 90 ]; then
            echo "OK: 内存使用正常 (使用率: ${mem_usage_percent}%)"
        else
            echo "WARNING: 内存使用过高 (使用率: ${mem_usage_percent}%)"
            all_ok=1
        fi
    else
        echo "WARNING: 无法获取内存信息"
        all_ok=1
    fi
    
    echo ""
    echo "=========================================="
    
    return $all_ok
}

# 执行检查
main "$@"
