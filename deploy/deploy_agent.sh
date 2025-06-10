#!/bin/bash

# 대상 서버 목록
SERVERS=(
    "192.168.198.131"  # vm1
    "192.168.198.133"  # bm1
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

    # collector.sh 최신 파일을 서버로 복사
    sshpass -p "$SSH_PASS" scp -o StrictHostKeyChecking=no ../collector/collector.sh $SSH_USER@$server:/tmp/collector.sh
    sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no $SSH_USER@$server "echo '$SSH_PASS' | sudo -S mv /tmp/collector.sh /usr/local/bin/collector.sh && echo '$SSH_PASS' | sudo -S chmod +x /usr/local/bin/collector.sh"

    # crontab에 collector.sh 등록 (매일 자정)
    sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no $SSH_USER@$server "(crontab -l 2>/dev/null; echo '0 0 * * * /usr/local/bin/collector.sh') | sort | uniq | crontab -"

    # 버전 정보 저장
    sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no $SSH_USER@$server "echo '$SSH_PASS' | sudo -S tee /var/log/osmanaged/agent_version > /dev/null"
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