#!/bin/sh
set -eu
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
release=${1:-61db65f7661b0ae9a9cff3e4cb59293ad17b7a73}
archive=${2:-/home/deploy/my-chuannong-backend-61db65f.tar.gz}
app=/opt/mychuannong
id mychuannong >/dev/null 2>&1 || useradd --system --home /var/lib/mychuannong --shell /usr/sbin/nologin mychuannong
install -d -m 755 "$app/releases/$release" /var/www/mychuannong-files /var/www/letsencrypt
install -d -m 750 -o mychuannong -g mychuannong /var/lib/mychuannong /var/lib/mychuannong/uploads /var/log/mychuannong /var/backups/mychuannong
install -d -m 750 -o root -g mychuannong /etc/mychuannong
tar -xzf "$archive" -C "$app/releases/$release" --no-same-owner
python3 "$app/releases/$release/tools/verify_checkout.py"
test -x "$app/venv/bin/python" || python3 -m venv "$app/venv"
"$app/venv/bin/python" -m pip install --disable-pip-version-check -r "$app/releases/$release/requirements.lock.txt"
ln -sfn "releases/$release" "$app/current"
cat > /etc/systemd/system/mychuannong-backend.service <<'SERVICE'
[Unit]
Description=MyChuannong independent platform backend
After=network.target

[Service]
Type=simple
User=mychuannong
Group=mychuannong
WorkingDirectory=/opt/mychuannong/current
EnvironmentFile=/etc/mychuannong/production.env
Environment=PYTHONDONTWRITEBYTECODE=1
Environment=PYTHONUNBUFFERED=1
ExecStart=/opt/mychuannong/venv/bin/python /opt/mychuannong/current/production.py
Restart=on-failure
RestartSec=5
UMask=0027
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/mychuannong /var/log/mychuannong /var/backups/mychuannong

[Install]
WantedBy=multi-user.target
SERVICE
systemctl daemon-reload
echo 'Backend application and service installed; initialization and start remain separate.'
