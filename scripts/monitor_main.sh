#!/bin/bash
# 主监控脚本
# 整合服务健康检查、GPU监控和告警通知

SCRIPT_DIR="/media/lz/baba/monitor/scripts"
LOG_DIR="/media/lz/baba/monitor/logs"
CONFIG_DIR="/media/lz/baba/monitor/config"

# 确保目录存在
mkdir -p "$LOG_DIR"

# 导入告警通知模块
source "$SCRIPT_DIR/alert_notify.sh"

# 监控间隔（秒）
MONITOR_INTERVAL=30

# 是否启用GPU监控
ENABLE_GPU_MONITOR=true

# 是否启用服务监控
ENABLE_SERVICE_MONITOR=true

# 日志文件
MAIN_LOG_FILE="$LOG_DIR/monitor_main_$(date '+%Y%m%d').log"

# 记录主日志
main_log() {
    local message=$1
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $message" >> "$MAIN_LOG_FILE"
}

# 执行服务健康检查
run_service_check() {
    main_log "开始执行服务健康检查..."
    
    local result=$("$SCRIPT_DIR/check_services.sh")
    local exit_code=$?
    
    echo "$result"
    
    # 分析结果，提取告警信息
    echo "$result" | while read -r line; do
        if echo "$line" | grep -q "ERROR"; then
            local service_name=$(echo "$line" | awk '{print $3}')
            send_alert "ERROR" "服务异常" "$line"
            main_log "服务告警: $line"
        elif echo "$line" | grep -q "WARNING"; then
            send_alert "WARNING" "服务警告" "$line"
            main_log "服务警告: $line"
        fi
    done
    
    if [ $exit_code -eq 0 ]; then
        log_message "INFO" "服务健康检查完成，所有服务状态正常"
        main_log "服务健康检查完成，所有服务状态正常"
    else
        log_message "WARNING" "服务健康检查完成，存在异常状态"
        main_log "服务健康检查完成，存在异常状态"
    fi
    
    return $exit_code
}

# 执行GPU监控
run_gpu_check() {
    main_log "开始执行GPU监控..."
    
    local result=$("$SCRIPT_DIR/check_gpu.sh")
    local exit_code=$?
    
    echo "$result"
    
    # 分析结果，提取告警信息
    echo "$result" | while read -r line; do
        if echo "$line" | grep -q "ERROR"; then
            send_alert "ERROR" "GPU异常" "$line"
            main_log "GPU告警: $line"
        elif echo "$line" | grep -q "WARNING"; then
            send_alert "WARNING" "GPU警告" "$line"
            main_log "GPU警告: $line"
        fi
    done
    
    if [ $exit_code -eq 0 ]; then
        log_message "INFO" "GPU监控完成，状态正常"
        main_log "GPU监控完成，状态正常"
    else
        log_message "WARNING" "GPU监控完成，存在异常状态"
        main_log "GPU监控完成，存在异常状态"
    fi
    
    return $exit_code
}

# 单次监控执行
run_single_monitor() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    log_message "INFO" "========================================"
    log_message "INFO" "开始监控周期 - $timestamp"
    log_message "INFO" "========================================"
    
    main_log "========================================"
    main_log "开始监控周期 - $timestamp"
    main_log "========================================"
    
    local overall_status=0
    
    # 执行服务监控
    if [ "$ENABLE_SERVICE_MONITOR" = true ]; then
        run_service_check
        if [ $? -ne 0 ]; then
            overall_status=1
        fi
    fi
    
    # 执行GPU监控
    if [ "$ENABLE_GPU_MONITOR" = true ]; then
        run_gpu_check
        if [ $? -ne 0 ]; then
            overall_status=1
        fi
    fi
    
    log_message "INFO" "========================================"
    log_message "INFO" "监控周期结束 - $timestamp"
    log_message "INFO" "========================================"
    
    main_log "========================================"
    main_log "监控周期结束 - $timestamp"
    main_log "========================================"
    
    return $overall_status
}

# 连续监控模式
run_continuous_monitor() {
    log_message "INFO" "启动连续监控模式，间隔: ${MONITOR_INTERVAL}秒"
    main_log "启动连续监控模式，间隔: ${MONITOR_INTERVAL}秒"
    
    while true; do
        run_single_monitor
        sleep "$MONITOR_INTERVAL"
    done
}

# 显示状态摘要
show_status_summary() {
    echo ""
    echo "========================================"
    echo "            系统监控状态摘要"
    echo "========================================"
    
    # 服务状态
    echo ""
    echo "[服务状态]"
    systemctl is-active --quiet llama-server && echo "✓ llama-server: 运行中" || echo "✗ llama-server: 未运行"
    systemctl is-active --quiet local-agent && echo "✓ local-agent: 运行中" || echo "✗ local-agent: 未运行"
    systemctl is-active --quiet local_agent_mcp && echo "✓ local_agent_mcp: 运行中" || echo "✗ local_agent_mcp: 未运行"
    
    # GPU状态
    echo ""
    echo "[GPU状态]"
    if command -v nvidia-smi &> /dev/null; then
        nvidia-smi --query-gpu=name,temperature.gpu,memory.used,memory.total --format=csv | tail -n +2
    else
        echo "nvidia-smi 不可用"
    fi
    
    # 资源使用
    echo ""
    echo "[系统资源]"
    local cpu_idle=$(top -bn1 | grep 'Cpu(s)' | sed 's/.*, *\([0-9.]*\)%* id.*/\1/')
    local cpu_usage=$(echo "100 - $cpu_idle" | bc | cut -d. -f1)
    echo "CPU使用率: ${cpu_usage}%"
    
    # 使用free命令获取内存信息，兼容中英文输出
    local mem_info=$(free -m | grep -E "^(Mem|内存)" | head -n 1)
    local mem_total=$(echo "$mem_info" | awk '{print $2}')
    local mem_used=$(echo "$mem_info" | awk '{print $3}')
    
    if [ -n "$mem_total" ] && [ "$mem_total" -gt 0 ]; then
        local mem_usage_percent=$((mem_used * 100 / mem_total))
        echo "内存使用率: ${mem_usage_percent}%"
    else
        echo "内存使用率: 无法获取"
    fi
    
    echo "磁盘使用率: $(df -h / | tail -1 | awk '{print $5}')"
    
    echo ""
    echo "========================================"
}

# 显示帮助信息
show_help() {
    echo "系统监控脚本使用方法:"
    echo ""
    echo "命令格式:"
    echo "  $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -h, --help          显示帮助信息"
    echo "  -s, --single        执行单次监控"
    echo "  -c, --continuous    启动连续监控模式"
    echo "  -t, --status        显示当前状态摘要"
    echo "  --no-gpu            禁用GPU监控"
    echo "  --no-service        禁用服务监控"
    echo ""
    echo "示例:"
    echo "  $0 -s               # 执行单次完整监控"
    echo "  $0 -c               # 启动连续监控"
    echo "  $0 -t               # 查看当前状态"
    echo "  $0 -s --no-gpu      # 只执行服务监控"
    echo ""
    echo "配置文件:"
    echo "  $CONFIG_DIR/email.conf    # 邮件告警配置"
    echo ""
    echo "日志目录:"
    echo "  $LOG_DIR                  # 监控日志"
}

# 主函数
main() {
    local mode="single"
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -s|--single)
                mode="single"
                ;;
            -c|--continuous)
                mode="continuous"
                ;;
            -t|--status)
                show_status_summary
                exit 0
                ;;
            --no-gpu)
                ENABLE_GPU_MONITOR=false
                ;;
            --no-service)
                ENABLE_SERVICE_MONITOR=false
                ;;
            *)
                echo "未知选项: $1"
                show_help
                exit 1
                ;;
        esac
        shift
    done
    
    # 根据模式执行
    case $mode in
        single)
            run_single_monitor
            ;;
        continuous)
            run_continuous_monitor
            ;;
    esac
}

# 执行主函数
main "$@"
