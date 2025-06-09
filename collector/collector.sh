#!/bin/bash

# 서버명 직접 지정 (이 파일을 각 서버에 맞게 수정)
SERVER_NAME="$(hostname)"
# SERVER_NAME="bm1" # 필요시 직접 지정

# 로그 디렉토리 설정
LOG_DIR="/var/log/osmanaged/$(date +%Y)/$(date +%m)"
mkdir -p $LOG_DIR

# 로그 파일 설정
LOG_FILE="$LOG_DIR/${SERVER_NAME}_$(date +%Y-%m-%d).log"

# 로그 함수
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> $LOG_FILE
}

# 1. 네트워크 정보
collect_network_info() {
    log "==== 1. 네트워크 정보 ===="
    ip addr show | grep 'inet ' | grep -v '127.0.0.1' | awk '{print "IP Address: "$2}' | while read line; do log "$line"; done
    log "Gateway: $(ip route | grep default | awk '{print $3}')"
    log "DNS: $(cat /etc/resolv.conf | grep nameserver | awk '{print $2}' | paste -sd ',' -)"
    log ""
}

# 2. USER 정보
collect_user_info() {
    log "==== 2. USER 정보 ===="
    while IFS=: read -r username _ _ _ _ _ _ _; do
        if [ -n "$username" ]; then
            expire=$(chage -l "$username" 2>/dev/null | grep "Password expires" | awk -F: '{print $2}' | xargs)
            if [ -n "$expire" ]; then
                log "$username: Password expires : $expire"
            fi
        fi
    done < /etc/passwd
    log ""
}

# 3. OS 버전
collect_os_info() {
    log "==== 3. OS 버전 ===="
    log "OS Version: $(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)"
    log "Kernel Version: $(uname -r)"
    log ""
}

# 4. MEM / DISK 사용량
collect_resource_usage() {
    log "==== 4. MEM / DISK 사용량 ===="
    log "Memory Usage:"
    free -h | awk 'NR==1 || NR==2 {print $0}' | while read line; do log "$line"; done
    log "Disk Usage:"
    df -h --output=source,size,used,avail,pcent,target -x tmpfs -x devtmpfs | awk 'NR==1 || NR>1 {print $0}' | while read line; do log "$line"; done
    log ""
}

# 5. Firewall · iptables 상태
collect_firewall_status() {
    log "==== 5. Firewall · iptables 상태 ===="
    if command -v ufw &> /dev/null; then
        log "UFW: $(ufw status | grep Status)"
    fi
    log "iptables:"
    iptables -L -n | grep -E 'Chain|ACCEPT|DROP' | while read line; do log "$line"; done
    log ""
}

# 6. Proxy 설정
collect_proxy_settings() {
    log "==== 6. Proxy 설정 ===="
    env | grep -i proxy | while read line; do log "$line"; done
    if [ -f /etc/environment ]; then
        grep -i proxy /etc/environment | while read line; do log "$line"; done
    fi
    log ""
}

# 7. Crontab 설정
collect_crontab() {
    log "==== 7. Crontab 설정 ===="
    for user in $(cut -f1 -d: /etc/passwd); do
        crontab -u $user -l 2>/dev/null | grep -v "no crontab" | while read line; do log "$user: $line"; done
    done
    log ""
}

# 8. NTP 설정
collect_ntp() {
    log "==== 8. NTP 설정 ===="
    if command -v timedatectl &> /dev/null; then
        log "$(timedatectl | grep 'NTP synchronized')"
    fi
    if [ -f /etc/ntp.conf ]; then
        grep -v '^#' /etc/ntp.conf | grep -v '^$' | while read line; do log "$line"; done
    fi
    log ""
}

# 9. 최근 패키지 업데이트
collect_package_updates() {
    log "==== 9. 최근 패키지 업데이트 ===="
    if command -v apt &> /dev/null; then
        grep -i "upgrade" /var/log/apt/history.log 2>/dev/null | tail -n 10 | while read line; do log "$line"; done
    elif command -v yum &> /dev/null; then
        yum history 2>/dev/null | head -n 10 | while read line; do log "$line"; done
    fi
    log ""
}

# 10. 설치된 패키지
collect_installed_packages() {
    log "==== 10. 설치된 패키지 ===="
    if command -v dpkg &> /dev/null; then
        dpkg -l | awk '{print $2, $3}' | tail -n +6 | head -n 10 | while read line; do log "$line"; done
    elif command -v rpm &> /dev/null; then
        rpm -qa | head -n 10 | while read line; do log "$line"; done
    fi
    log "... (생략)"
    log ""
}

# 11. 어제 OS 접근 기록
collect_access_logs() {
    log "==== 11. 어제 OS 접근 기록 ===="
    yesterday=$(date -d "yesterday" +%Y-%m-%d)
    grep "$yesterday" /var/log/auth.log 2>/dev/null | head -n 10 | while read line; do log "$line"; done
    log "... (생략)"
    log ""
}

# 12. 프로세스 상태
collect_process_status() {
    log "==== 12. 프로세스 상태 ===="
    ps aux --sort=-%mem | awk 'NR==1 || NR<=11' | while read line; do log "$line"; done
    log "... (상위 10개만 표시)"
    log ""
}

# 13. 서비스 포트 상태(Ipv4)
collect_port_status() {
    log "==== 13. 서비스 포트 상태(Ipv4) ===="
    if command -v netstat &> /dev/null; then
        netstat -tuln4 | awk 'NR==1 || NR>1' | while read line; do log "$line"; done
    elif command -v ss &> /dev/null; then
        ss -tuln4 | awk 'NR==1 || NR>1' | while read line; do log "$line"; done
    fi
    log ""
}

# 14. System Log (Error/Fail/Warn/Fault)
collect_system_logs() {
    log "==== 14. System Log (Error/Fail/Warn/Fault) ===="
    grep -i "error\|fail\|warn\|fault" /var/log/syslog 2>/dev/null | head -n 10 | while read line; do log "$line"; done
    log "... (생략)"
    log ""
}

# 메인 실행
main() {
    log ""
    collect_network_info
    collect_user_info
    collect_os_info
    collect_resource_usage
    collect_firewall_status
    collect_proxy_settings
    collect_crontab
    collect_ntp
    collect_package_updates
    collect_installed_packages
    collect_access_logs
    collect_process_status
    collect_port_status
    collect_system_logs
    log "수집 완료"
}

# 스크립트 실행
main 