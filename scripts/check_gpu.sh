#!/bin/bash
# GPU监控脚本
# 监控GPU显存使用和温度状态

LOG_DIR="/media/lz/baba/monitor/logs"
SCRIPT_DIR="/media/lz/baba/monitor/scripts"

# 确保日志目录存在
mkdir -p "$LOG_DIR"

# GPU温度警告阈值（摄氏度）
TEMP_WARNING_THRESHOLD=80
TEMP_CRITICAL_THRESHOLD=90

# GPU显存警告阈值（百分比）
MEM_WARNING_THRESHOLD=90

# 检查GPU状态
check_gpu() {
    local all_ok=0
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "=========================================="
    echo "GPU状态监控 - $timestamp"
    echo "=========================================="
    
    # 检查nvidia-smi是否可用
    if ! command -v nvidia-smi &> /dev/null; then
        echo "ERROR: nvidia-smi 命令不可用，GPU监控无法执行"
        return 1
    fi
    
    # 测试nvidia-smi是否正常工作
    local nvidia_test=$(nvidia-smi -L 2>&1)
    if echo "$nvidia_test" | grep -q "failed"; then
        echo "ERROR: NVIDIA驱动未正常运行，请检查驱动安装"
        echo "       $nvidia_test"
        return 1
    fi
    
    # 获取GPU数量
    local gpu_count=$(echo "$nvidia_test" | wc -l)
    
    if [ -z "$gpu_count" ] || [ "$gpu_count" -eq 0 ]; then
        echo "ERROR: 无法获取GPU数量或未检测到GPU"
        return 1
    fi
    
    echo ""
    echo "[GPU数量]: $gpu_count"
    
    # 遍历每个GPU
    for ((i=0; i<gpu_count; i++)); do
        echo ""
        echo "[GPU $i 状态]"
        
        # 获取GPU名称
        local gpu_name=$(nvidia-smi --query-gpu=name --format=csv,noheader -i $i 2>/dev/null)
        echo "  名称: $gpu_name"
        
        # 获取GPU温度
        local gpu_temp=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader -i $i 2>/dev/null)
        echo "  温度: ${gpu_temp}C"
        
        # 温度检查
        if [ -n "$gpu_temp" ] && [ "$gpu_temp" -ge "$TEMP_CRITICAL_THRESHOLD" ] 2>/dev/null; then
            echo "  ERROR: GPU温度过高 (${gpu_temp}C)，已超过临界阈值 ${TEMP_CRITICAL_THRESHOLD}C"
            all_ok=1
        elif [ -n "$gpu_temp" ] && [ "$gpu_temp" -ge "$TEMP_WARNING_THRESHOLD" ] 2>/dev/null; then
            echo "  WARNING: GPU温度偏高 (${gpu_temp}C)，接近警告阈值 ${TEMP_WARNING_THRESHOLD}C"
            all_ok=1
        elif [ -n "$gpu_temp" ]; then
            echo "  OK: GPU温度正常 (${gpu_temp}C)"
        else
            echo "  WARNING: 无法获取GPU温度"
        fi
        
        # 获取GPU显存使用
        local mem_info=$(nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader,nounits -i $i 2>/dev/null)
        local mem_used=$(echo "$mem_info" | awk '{print $1}')
        local mem_total=$(echo "$mem_info" | awk '{print $2}')
        
        if [ -n "$mem_used" ] && [ -n "$mem_total" ] && [ "$mem_total" -gt 0 ] 2>/dev/null; then
            local mem_usage_percent=$((mem_used * 100 / mem_total))
            echo "  显存使用: ${mem_used}MB / ${mem_total}MB (${mem_usage_percent}%)"
            
            # 显存检查
            if [ "$mem_usage_percent" -ge "$MEM_WARNING_THRESHOLD" ] 2>/dev/null; then
                echo "  WARNING: GPU显存使用率过高 (${mem_usage_percent}%)"
                all_ok=1
            else
                echo "  OK: GPU显存使用正常 (${mem_usage_percent}%)"
            fi
        else
            echo "  WARNING: 无法获取GPU显存信息"
        fi
        
        # 获取GPU功耗
        local power_info=$(nvidia-smi --query-gpu=power.draw,power.limit --format=csv,noheader,nounits -i $i 2>/dev/null)
        local power_used=$(echo "$power_info" | awk '{print $1}')
        local power_limit=$(echo "$power_info" | awk '{print $2}')
        
        if [ -n "$power_used" ] && [ -n "$power_limit" ]; then
            echo "  功耗: ${power_used}W / ${power_limit}W"
        else
            echo "  功耗: 无法获取"
        fi
        
        # 获取GPU利用率
        local gpu_util=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader -i $i 2>/dev/null | sed 's/%//')
        
        if [ -n "$gpu_util" ]; then
            echo "  利用率: ${gpu_util}%"
        else
            echo "  利用率: 无法获取"
        fi
    done
    
    # 获取进程占用情况
    echo ""
    echo "[GPU进程占用]"
    local gpu_processes=$(nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv,noheader 2>/dev/null)
    
    if [ -n "$gpu_processes" ]; then
        echo "$gpu_processes" | while read -r line; do
            if [ -n "$line" ]; then
                echo "  $line"
            fi
        done
    else
        echo "  无进程占用GPU"
    fi
    
    echo ""
    echo "=========================================="
    
    return $all_ok
}

# 执行检查
check_gpu "$@"
