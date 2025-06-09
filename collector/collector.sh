#!/bin/bash

# 서버명 직접 지정 (이 파일을 각 서버에 맞게 수정)
SERVER_NAME="$(hostname)"
# SERVER_NAME="bm1" # 필요시 직접 지정

# 로그 디렉토리 설정
LOG_DIR="/var/log/osmanaged/$(date +%Y)/$(date +%m)"
mkdir -p $LOG_DIR

# 로그 파일 설정
LOG_FILE="$LOG_DIR/${SERVER_NAME}_$(date +%Y-%m-%d).log"

# 로그 함수 (타임스탬프 없이)
log() {
    echo "$1" >> $LOG_FILE
}

# 1. 네트워크 정보
collect_network_info() {
    log "=== Network Information ==="
    ip=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '^127' | head -n 1)
    log "IP Address: $ip"
    gw=$(ip route | grep default | awk '{print $3}')
    log "Gateway: $gw"
    dns=$(grep nameserver /etc/resolv.conf | awk '{print $2}' | paste -sd ',' -)
    log "DNS: $dns"
    log ""
}

# 2. USER 정보
collect_user_info() {
    log "=== User Information ==="
    getent passwd | awk -F: '$3 >= 1000 && $1 != "nobody"' | cut -d: -f1 | while read username; do
        expire=$(chage -l "$username" 2>/dev/null | grep "Password expires" | awk -F: '{print $2}' | xargs)
        if [ -n "$expire" ]; then
            log "$username: Password expires : $expire"
        fi
    done | head -n 5
    log "... (최대 5명만 표시)"
    log ""
}

# 3. OS 버전
collect_os_info() {
    log "=== OS Information ==="
    log "OS Version: $(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)"
    log "Kernel Version: $(uname -r)"
    log ""
}

# 4. MEM / DISK 사용량
collect_resource_usage() {
    log "=== Resource Usage ==="
    mem=$(free -h | awk '/Mem:/ {print $3 "/" $2}')
    log "Memory Usage: $mem"
    df -h --output=target,pcent | grep -v 'Mounted' | head -n 5 | while read mp pct; do
        log "Disk $mp: $pct"
    done
    log "... (최대 5개 마운트만 표시)"
    log ""
}

# 5. Firewall · iptables 상태
collect_firewall_status() {
    log "=== Firewall Status ==="
    if command -v ufw &> /dev/null; then
        log "UFW: $(ufw status | grep Status)"
    fi
    log "iptables INPUT: $(iptables -L INPUT -n | grep -E 'ACCEPT|DROP' | wc -l) rules"
    log ""
}

# 6. Proxy 설정
collect_proxy_settings() {
    log "=== Proxy Settings ==="
    env | grep -i proxy | head -n 5 | while read line; do log "$line"; done
    if [ -f /etc/environment ]; then
        grep -i proxy /etc/environment | head -n 5 | while read line; do log "$line"; done
    fi
    log "... (최대 5줄만 표시)"
    log ""
}

# 7. Crontab 설정
collect_crontab() {
    log "=== Crontab Settings ==="
    getent passwd | awk -F: '$3 >= 1000 && $1 != "nobody"' | cut -d: -f1 | while read user; do
        crontab -u $user -l 2>/dev/null | grep -v "no crontab" | head -n 5 | while read line; do log "$user: $line"; done
    done
    log "... (최대 5줄만 표시)"
    log ""
}

# 8. NTP 설정
collect_ntp() {
    log "=== NTP Settings ==="
    if command -v timedatectl &> /dev/null; then
        log "$(timedatectl | grep 'NTP synchronized')"
    fi
    if [ -f /etc/ntp.conf ]; then
        grep -v '^#' /etc/ntp.conf | grep -v '^$' | head -n 5 | while read line; do log "$line"; done
    fi
    log "... (최대 5줄만 표시)"
    log ""
}

# 9. 최근 패키지 업데이트
collect_package_updates() {
    log "=== Recent Package Updates ==="
    if command -v apt &> /dev/null; then
        grep -i "upgrade" /var/log/apt/history.log 2>/dev/null | tail -n 5 | while read line; do log "$line"; done
    elif command -v yum &> /dev/null; then
        yum history 2>/dev/null | head -n 5 | while read line; do log "$line"; done
    fi
    log "... (최대 5줄만 표시)"
    log ""
}

# 10. 설치된 패키지
collect_installed_packages() {
    log "=== Installed Packages ==="
    if command -v dpkg &> /dev/null; then
        dpkg -l | awk 'NR>5 {print $2, $3}' | head -n 5 | while read line; do log "$line"; done
    elif command -v rpm &> /dev/null; then
        rpm -qa | head -n 5 | while read line; do log "$line"; done
    fi
    log "... (최대 5개만 표시)"
    log ""
}

# 11. 어제 OS 접근 기록
collect_access_logs() {
    log "=== Yesterday's Access Logs ==="
    yesterday=$(date -d "yesterday" +%Y-%m-%d)
    grep "$yesterday" /var/log/auth.log 2>/dev/null | head -n 5 | while read line; do log "$line"; done
    log "... (최대 5줄만 표시)"
    log ""
}

# 12. 프로세스 상태
collect_process_status() {
    log "=== Process Status ==="
    ps aux --sort=-%mem | awk 'NR==1 || NR<=6' | while read line; do log "$line"; done
    log "... (상위 5개만 표시)"
    log ""
}

# 13. 서비스 포트 상태(Ipv4)
collect_port_status() {
    log "=== Port Status ==="
    if command -v netstat &> /dev/null; then
        netstat -tuln4 | awk 'NR==1 || NR<=6' | while read line; do log "$line"; done
    elif command -v ss &> /dev/null; then
        ss -tuln4 | awk 'NR==1 || NR<=6' | while read line; do log "$line"; done
    fi
    log "... (상위 5개만 표시)"
    log ""
}

# 14. System Log (Error/Fail/Warn/Fault)
collect_system_logs() {
    log "=== System Log (Error/Fail/Warn/Fault) ==="
    grep -i "error\|fail\|warn\|fault" /var/log/syslog 2>/dev/null | head -n 5 | while read line; do log "$line"; done
    log "... (최대 5줄만 표시)"
    log ""
}

# 메인 실행
main() {
    > $LOG_FILE
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