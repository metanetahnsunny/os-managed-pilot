#!/bin/bash

# 대상 서버 목록
SERVERS=(
    "192.168.198.131"  # vm1
    "192.168.198.132"  # bm1
)

# SSH 접속 정보
SSH_USER="ahn"
SSH_PASS="ahn"

# 에이전트 버전
AGENT_VERSION="1.0.0"

# 로그 디렉토리
LOG_DIR="/var/log/osmanaged/deploy"
mkdir -p $LOG_DIR

# 로그 함수
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_DIR/deploy.log"
}

# 에이전트 배포 함수
deploy_agent() {
    local server=$1
    log "Deploying agent to $server"
    
    # sshpass를 사용하여 SSH로 서버에 접속하여 에이전트 설치
    sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no $SSH_USER@$server << 'EOF'
        # 로그 디렉토리 생성
        mkdir -p /var/log/osmanaged
        
        # collector 스크립트 복사
        cat > /usr/local/bin/collector.sh << 'EOSCRIPT'
        #!/bin/bash
        
        # 로그 디렉토리 설정
        LOG_DIR="/var/log/osmanaged/$(date +%Y)/$(date +%m)"
        mkdir -p $LOG_DIR
        
        # 로그 파일 설정
        LOG_FILE="$LOG_DIR/$(hostname)_$(date +%Y-%m-%d).log"
        
        # 로그 함수
        log() {
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> $LOG_FILE
        }
        
        # 1. 네트워크 정보 수집
        collect_network_info() {
            log "=== Network Information ==="
            log "IP Address: $(ip addr show | grep 'inet ' | grep -v '127.0.0.1')"
            log "Gateway: $(ip route | grep default | awk '{print $3}')"
            log "DNS: $(cat /etc/resolv.conf | grep nameserver | awk '{print $2}')"
        }
        
        # 2. USER 정보 수집
        collect_user_info() {
            log "=== User Information ==="
            while IFS=: read -r username _ _ _ _ _ _ _; do
                if [ -n "$username" ]; then
                    chage -l "$username" 2>/dev/null | grep "Password expires" >> $LOG_FILE
                fi
            done < /etc/passwd
        }
        
        # 3. OS 버전
        collect_os_info() {
            log "=== OS Information ==="
            log "OS Version: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
            log "Kernel Version: $(uname -r)"
        }
        
        # 4. MEM / DISK 사용량
        collect_resource_usage() {
            log "=== Resource Usage ==="
            log "Memory Usage:"
            free -h >> $LOG_FILE
            log "Disk Usage:"
            df -h >> $LOG_FILE
        }
        
        # 5. Firewall 상태
        collect_firewall_status() {
            log "=== Firewall Status ==="
            if command -v ufw &> /dev/null; then
                ufw status >> $LOG_FILE
            elif command -v firewall-cmd &> /dev/null; then
                firewall-cmd --list-all >> $LOG_FILE
            fi
            iptables -L >> $LOG_FILE
        }
        
        # 6. Proxy 설정
        collect_proxy_settings() {
            log "=== Proxy Settings ==="
            env | grep -i proxy >> $LOG_FILE
            if [ -f /etc/environment ]; then
                grep -i proxy /etc/environment >> $LOG_FILE
            fi
        }
        
        # 7. Crontab 설정
        collect_crontab() {
            log "=== Crontab Settings ==="
            for user in $(cut -f1 -d: /etc/passwd); do
                crontab -u $user -l 2>/dev/null >> $LOG_FILE
            done
        }
        
        # 8. NTP 설정
        collect_ntp() {
            log "=== NTP Settings ==="
            if command -v timedatectl &> /dev/null; then
                timedatectl status >> $LOG_FILE
            fi
            if [ -f /etc/ntp.conf ]; then
                grep -v '^#' /etc/ntp.conf >> $LOG_FILE
            fi
        }
        
        # 9. 최근 패키지 업데이트
        collect_package_updates() {
            log "=== Recent Package Updates ==="
            if command -v apt &> /dev/null; then
                grep -i "upgrade" /var/log/apt/history.log | tail -n 20 >> $LOG_FILE
            elif command -v yum &> /dev/null; then
                yum history | head -n 20 >> $LOG_FILE
            fi
        }
        
        # 10. 설치된 패키지
        collect_installed_packages() {
            log "=== Installed Packages ==="
            if command -v dpkg &> /dev/null; then
                dpkg -l >> $LOG_FILE
            elif command -v rpm &> /dev/null; then
                rpm -qa >> $LOG_FILE
            fi
        }
        
        # 11. 어제 OS 접근 기록
        collect_access_logs() {
            log "=== Yesterday's Access Logs ==="
            yesterday=$(date -d "yesterday" +%Y-%m-%d)
            grep "$yesterday" /var/log/auth.log >> $LOG_FILE
        }
        
        # 12. 프로세스 상태
        collect_process_status() {
            log "=== Process Status ==="
            ps aux >> $LOG_FILE
        }
        
        # 13. 서비스 포트 상태
        collect_port_status() {
            log "=== Port Status ==="
            netstat -tuln >> $LOG_FILE
        }
        
        # 14. System Log
        collect_system_logs() {
            log "=== System Logs ==="
            grep -i "error\|fail\|warn\|fault" /var/log/syslog >> $LOG_FILE
        }
        
        # 메인 실행
        main() {
            log "Starting collection for $(hostname)"
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
            log "Collection completed"
        }
        
        # 스크립트 실행
        main
EOSCRIPT
        
        # 실행 권한 부여
        chmod +x /usr/local/bin/collector.sh
        
        # crontab에 등록 (매일 자정에 실행)
        (crontab -l 2>/dev/null; echo "0 0 * * * /usr/local/bin/collector.sh") | crontab -
        
        # 버전 정보 저장
        echo "$AGENT_VERSION" > /var/log/osmanaged/agent_version
EOF
    
    if [ $? -eq 0 ]; then
        log "Successfully deployed agent to $server"
    else
        log "Failed to deploy agent to $server"
    fi
}

# 메인 실행
main() {
    log "Starting agent deployment"
    
    for server in "${SERVERS[@]}"; do
        deploy_agent $server
    done
    
    log "Agent deployment completed"
}

# 스크립트 실행
main 