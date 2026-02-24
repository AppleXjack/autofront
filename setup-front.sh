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
curl https://nginx.org/keys/nginx_signing.key | apt-key add -
echo "deb https://nginx.org/packages/ubuntu $(lsb_release -cs) nginx" | tee /etc/apt/sources.list.d/nginx.list
apt update
apt install nginx -y

echo "=== Пишем конфиг ==="
cat > /etc/nginx/nginx.conf <<NGINX
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /run/nginx.pid;

events {
    worker_connections 1024;
}

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
ss -tlunp | grep 443
echo "Фронт настроен -> ${BACKEND_IP}:443"
