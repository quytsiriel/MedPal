import paramiko

host = "124.197.18.57"
password = "Daiduong2006!"

content_1 = '''[Service]
Environment="OLLAMA_HOST=0.0.0.0:11434"
'''

content_2 = '''[Unit]
Description=Ollama Service 2
After=network-online.target

[Service]
ExecStart=/usr/local/bin/ollama serve
User=ollama
Group=ollama
Restart=always
RestartSec=3
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin"
Environment="OLLAMA_HOST=0.0.0.0:11435"

[Install]
WantedBy=default.target
'''

content_3 = '''[Unit]
Description=Ollama Service 3
After=network-online.target

[Service]
ExecStart=/usr/local/bin/ollama serve
User=ollama
Group=ollama
Restart=always
RestartSec=3
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin"
Environment="OLLAMA_HOST=0.0.0.0:11436"

[Install]
WantedBy=default.target
'''

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect(host, username="root", password=password, timeout=10)

sftp = client.open_sftp()
with sftp.file('/tmp/override1.conf', 'w') as f:
    f.write(content_1)
with sftp.file('/tmp/ollama2.service', 'w') as f:
    f.write(content_2)
with sftp.file('/tmp/ollama3.service', 'w') as f:
    f.write(content_3)
sftp.close()

commands = [
    "sudo cp /tmp/override1.conf /etc/systemd/system/ollama.service.d/override.conf",
    "sudo cp /tmp/ollama2.service /etc/systemd/system/ollama2.service",
    "sudo cp /tmp/ollama3.service /etc/systemd/system/ollama3.service",
    "sudo systemctl daemon-reload",
    "sudo systemctl enable ollama2",
    "sudo systemctl enable ollama3",
    "sudo systemctl restart ollama",
    "sudo systemctl restart ollama2",
    "sudo systemctl restart ollama3",
    "sleep 2",
    "netstat -tlnp | grep 1143"
]

for cmd in commands:
    print(f"Executing: {cmd}")
    stdin, stdout, stderr = client.exec_command(cmd)
    out = stdout.read().decode('utf-8', errors='ignore')
    if out: print(out)

client.close()
