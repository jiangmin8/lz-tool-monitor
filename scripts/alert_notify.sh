#!/bin/bash
# 告警通知模块
# 支持日志记录和邮件通知

LOG_DIR="/media/lz/baba/monitor/logs"
CONFIG_DIR="/media/lz/baba/monitor/config"

# 确保日志目录存在
mkdir -p "$LOG_DIR"

# 告警级别定义
declare -A ALERT_LEVELS=(
    ["INFO"]="\033[0;32m"
    ["WARNING"]="\033[0;33m"
    ["ERROR"]="\033[0;31m"
    ["CRITICAL"]="\033[1;31m"
    ["RESET"]="\033[0m"
)

# 获取日志文件名（按日期）
get_log_filename() {
    echo "$LOG_DIR/monitor_$(date '+%Y%m%d').log"
}

# 获取告警日志文件名
get_alert_log_filename() {
    echo "$LOG_DIR/alerts_$(date '+%Y%m%d').log"
}

# 日志记录函数
log_message() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_file=$(get_log_filename)
    
    # 控制台输出（带颜色）
    echo -e "${ALERT_LEVELS[$level]}[$timestamp] [$level] $message${ALERT_LEVELS[RESET]}"
    
    # 写入日志文件（不带颜色）
    echo "[$timestamp] [$level] $message" >> "$log_file"
    
    # 如果是告警级别，写入告警日志
    if [ "$level" = "WARNING" ] || [ "$level" = "ERROR" ] || [ "$level" = "CRITICAL" ]; then
        local alert_file=$(get_alert_log_filename)
        echo "[$timestamp] [$level] $message" >> "$alert_file"
    fi
}

# 发送邮件通知
send_email() {
    local subject=$1
    local body=$2
    
    # 检查配置文件
    local config_file="$CONFIG_DIR/email.conf"
    
    if [ ! -f "$config_file" ]; then
        log_message "WARNING" "邮件配置文件不存在: $config_file"
        return 1
    fi
    
    # 读取配置
    source "$config_file"
    
    if [ -z "$SMTP_SERVER" ] || [ -z "$SMTP_PORT" ] || [ -z "$SMTP_USER" ] || [ -z "$SMTP_PASS" ] || [ -z "$TO_EMAIL" ]; then
        log_message "WARNING" "邮件配置不完整"
        return 1
    fi
    
    # 使用sendmail或ssmtp发送邮件
    if command -v sendmail &> /dev/null; then
        echo -e "Subject: $subject\n\n$body" | sendmail "$TO_EMAIL"
        if [ $? -eq 0 ]; then
            log_message "INFO" "邮件已发送至: $TO_EMAIL"
            return 0
        else
            log_message "ERROR" "邮件发送失败"
            return 1
        fi
    elif command -v ssmtp &> /dev/null; then
        echo -e "To: $TO_EMAIL\nFrom: $SMTP_USER\nSubject: $subject\n\n$body" | ssmtp "$TO_EMAIL"
        if [ $? -eq 0 ]; then
            log_message "INFO" "邮件已发送至: $TO_EMAIL"
            return 0
        else
            log_message "ERROR" "邮件发送失败"
            return 1
        fi
    else
        log_message "WARNING" "系统未安装邮件客户端(sendmail/ssmtp)"
        return 1
    fi
}

# 发送告警通知
send_alert() {
    local level=$1
    local subject=$2
    local message=$3
    
    # 记录日志
    log_message "$level" "$message"
    
    # 如果是严重告警，发送邮件
    if [ "$level" = "ERROR" ] || [ "$level" = "CRITICAL" ]; then
        send_email "【监控告警】$level - $subject" "$message"
    fi
}

# 写入状态报告
write_status_report() {
    local report_content=$1
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local report_file="$LOG_DIR/status_report_$(date '+%Y%m%d').log"
    
    echo "==========================================" >> "$report_file"
    echo "状态报告 - $timestamp" >> "$report_file"
    echo "==========================================" >> "$report_file"
    echo "$report_content" >> "$report_file"
    echo "" >> "$report_file"
}

# 清理旧日志（保留最近7天）
clean_old_logs() {
    find "$LOG_DIR" -name "*.log" -type f -mtime +7 -delete
    log_message "INFO" "已清理7天前的旧日志"
}

# 显示帮助信息
show_alert_help() {
    echo "告警通知模块使用方法:"
    echo "  log_message <级别> <消息>"
    echo "  send_alert <级别> <主题> <消息>"
    echo "  write_status_report <报告内容>"
    echo "  clean_old_logs"
    echo ""
    echo "告警级别: INFO, WARNING, ERROR, CRITICAL"
}

# 主函数
alert_main() {
    case "$1" in
        log_message)
            log_message "$2" "$3"
            ;;
        send_alert)
            send_alert "$2" "$3" "$4"
            ;;
        write_status_report)
            write_status_report "$2"
            ;;
        clean_old_logs)
            clean_old_logs
            ;;
        *)
            show_alert_help
            ;;
    esac
}

# 只有直接执行时才调用主函数
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    alert_main "$@"
fi
