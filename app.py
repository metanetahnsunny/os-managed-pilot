from flask import Flask, render_template, request, jsonify
import os
from datetime import datetime

app = Flask(__name__)
app.config['SECRET_KEY'] = os.urandom(24)

# 로그 디렉토리 설정
LOG_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'logs')

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/servers')
def servers():
    # TODO: 서버 목록을 JSON 파일이나 DB에서 가져오기
    servers = [
        {"name": "server1", "type": "VM", "status": "active"},
        {"name": "server2", "type": "BM", "status": "active"}
    ]
    return jsonify(servers)

@app.route('/logs/<server_name>')
def get_logs(server_name):
    date = request.args.get('date', datetime.now().strftime('%Y-%m-%d'))
    log_file = os.path.join(LOG_DIR, f'{server_name}_{date}.log')
    
    try:
        if os.path.exists(log_file):
            with open(log_file, 'r') as f:
                logs = f.readlines()
            return jsonify({"logs": logs})
        else:
            return jsonify({"logs": [f"No logs found for {server_name} on {date}"]})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/compare')
def compare_logs():
    server1 = request.args.get('server1')
    server2 = request.args.get('server2')
    date = request.args.get('date')
    # TODO: 로그 비교 로직 구현
    return jsonify({"diff": []})

if __name__ == '__main__':
    app.run(debug=True) 