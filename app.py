from flask import Flask, render_template, request, jsonify, send_file
import os
from datetime import datetime
import glob

app = Flask(__name__)
app.config['SECRET_KEY'] = os.urandom(24)

# 서버 설정
SERVERS = {
    "vm1": {"ip": "192.168.198.131", "type": "VM"},
    "bm1": {"ip": "192.168.198.133", "type": "BM"}
}

# 로그 디렉토리 설정
LOG_DIR = "/var/log/osmanaged"

# 로그 디렉토리가 없으면 생성
os.makedirs(LOG_DIR, exist_ok=True)

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/servers')
def get_servers():
    server_list = []
    for name, info in SERVERS.items():
        # 로그 파일 존재 여부 확인
        log_pattern = os.path.join(LOG_DIR, datetime.now().strftime('%Y'), 
                                 datetime.now().strftime('%m'), 
                                 f"{name}_*.log")
        log_files = glob.glob(log_pattern)
        status = "active" if log_files else "inactive"
        
        server_list.append({
            "name": name,
            "ip": info["ip"],
            "type": info["type"],
            "status": status
        })
    return jsonify(server_list)

@app.route('/logs/<server_name>')
def get_logs(server_name):
    if server_name not in SERVERS:
        return jsonify({"error": "Server not found"}), 404
        
    date = request.args.get('date', datetime.now().strftime('%Y-%m-%d'))
    year, month = date.split('-')[:2]
    log_dir = os.path.join(LOG_DIR, year, month)
    pattern = os.path.join(log_dir, f"*{server_name}*_{date}.log")
    log_files = glob.glob(pattern)
    try:
        if log_files:
            with open(log_files[0], 'r') as f:
                logs = f.readlines()
            return jsonify({"logs": logs})
        else:
            return jsonify({"logs": [f"No logs found for {server_name} on {date}"]})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/download/<server_name>')
def download_log(server_name):
    if server_name not in SERVERS:
        return jsonify({"error": "Server not found"}), 404
        
    date = request.args.get('date', datetime.now().strftime('%Y-%m-%d'))
    year, month = date.split('-')[:2]
    log_dir = os.path.join(LOG_DIR, year, month)
    pattern = os.path.join(log_dir, f"*{server_name}*_{date}.log")
    log_files = glob.glob(pattern)
    if log_files:
        return send_file(log_files[0], as_attachment=True, 
                        download_name=os.path.basename(log_files[0]))
    else:
        return jsonify({"error": "Log file not found"}), 404

@app.route('/compare')
def compare_logs():
    server1 = request.args.get('server1')
    server2 = request.args.get('server2')
    date = request.args.get('date')
    
    if not all([server1, server2, date]):
        return jsonify({"error": "Missing parameters"}), 400
        
    if server1 not in SERVERS or server2 not in SERVERS:
        return jsonify({"error": "Server not found"}), 404
    
    year, month = date.split('-')[:2]
    log_dir = os.path.join(LOG_DIR, year, month)
    pattern1 = os.path.join(log_dir, f"*{server1}*_{date}.log")
    pattern2 = os.path.join(log_dir, f"*{server2}*_{date}.log")
    log_files1 = glob.glob(pattern1)
    log_files2 = glob.glob(pattern2)
    try:
        if log_files1 and log_files2:
            with open(log_files1[0], 'r') as f1, open(log_files2[0], 'r') as f2:
                diff = []
                for line1, line2 in zip(f1, f2):
                    if line1 != line2:
                        diff.append({
                            "server1": line1.strip(),
                            "server2": line2.strip()
                        })
            return jsonify({"diff": diff})
        else:
            return jsonify({"error": "One or both log files not found"}), 404
    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True) 