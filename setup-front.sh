#!/bin/bash
set -e

BACKEND_IP=$1

if [ -z "$BACKEND_IP" ]; then
    echo "Использование: setup-front.sh <IP бэкенда>"
    exit 1
fi

echo "=== Удаляем старый nginx ==="
apt remove nginx nginx-common nginx-core -y 2>/dev/null || true

echo "=== Устанавливаем официальный nginx ==="
apt update
apt install curl gnupg2 ca-certificates lsb-release -y

curl -fsSL https://nginx.org/keys/nginx_signing.key | gpg --dearmor -o /etc/apt/trusted.gpg.d/nginx.gpg
echo "deb https://nginx.org/packages/ubuntu $(lsb_release -cs) nginx" | tee /etc/apt/sources.list.d/nginx.list
apt update
apt install nginx -y

echo "=== Создаём заглушку ==="
mkdir -p /var/www/stub
cat > /var/www/stub/index.html <<'HTML'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Welcome</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
            background: #f5f5f5;
            display: flex;
            align-items: center;
            justify-content: center;
            min-height: 100vh;
            color: #333;
        }
        .container {
            text-align: center;
            padding: 40px;
        }
        h1 { font-size: 2rem; font-weight: 300; margin-bottom: 12px; }
        p  { color: #888; font-size: 0.95rem; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Welcome</h1>
        <p>Service is running.</p>
    </div>
</body>
</html>
HTML

echo "=== Пишем конфиг ==="
cat > /etc/nginx/nginx.conf <<NGINX
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /run/nginx.pid;

events {
    worker_connections 1024;
}

# HTTP — заглушка на порту 80
http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    server {
        listen 80 default_server;

        location / {
            root /var/www/stub;
            index index.html;
        }
    }
}

# TCP/UDP — прозрачный проброс 443 на бэкенд
stream {
    upstream backend {
        server ${BACKEND_IP}:443;
    }

    server {
        listen 443;
        proxy_pass backend;
        proxy_socket_keepalive on;
        proxy_timeout 1h;
        proxy_connect_timeout 10s;
        proxy_buffer_size 16k;
        ssl_preread on;
    }

    server {
        listen 443 udp reuseport;
        proxy_pass backend;
        proxy_timeout 1h;
    }
}
NGINX

echo "=== Запускаем ==="
nginx -t
systemctl enable nginx
systemctl restart nginx

echo "=== Готово! Проверка порта ==="
ss -tlunp | grep -E '80|443'
echo "Фронт настроен -> ${BACKEND_IP}:443"
