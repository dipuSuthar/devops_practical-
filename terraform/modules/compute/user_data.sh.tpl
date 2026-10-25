#!/bin/bash
set -euxo pipefail
export HOME=/root
dnf install -y nodejs20 nodejs20-npm unzip

NODE=$(command -v node || command -v node-20)
NPM=$(command -v npm || command -v npm-20)

mkdir -p /opt/app && cd /opt/app
aws s3 cp s3://${releases_bucket}/${release_key} app.zip --region ${region}
unzip -o app.zip
$NPM install --omit=dev

cat > /etc/systemd/system/app.service <<UNIT
[Unit]
Description=DevOps task app (${color} ${version})
After=network-online.target

[Service]
WorkingDirectory=/opt/app
Environment=PORT=${app_port}
Environment=AWS_REGION=${region}
Environment=DB_SECRET_ARN=${secret_arn}
Environment=APP_BUCKET=${app_bucket}
Environment=APP_VERSION=${version}
Environment=APP_COLOR=${color}
ExecStart=$NODE server.js
Restart=always
User=nobody

[Install]
WantedBy=multi-user.target
UNIT

chown -R nobody:nobody /opt/app
systemctl daemon-reload
systemctl enable --now app
