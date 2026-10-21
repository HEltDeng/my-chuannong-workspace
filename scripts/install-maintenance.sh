#!/bin/sh
set -eu
install -m 644 /home/deploy/mychuannong-backup-production.py /opt/mychuannong/backup.py
cat > /etc/systemd/system/mychuannong-backup.service <<'SERVICE'
[Unit]
Description=MyChuannong daily verified SQLite backup
After=mychuannong-backend.service

[Service]
Type=oneshot
User=mychuannong
Group=mychuannong
Environment=PYTHONDONTWRITEBYTECODE=1
ExecStart=/opt/mychuannong/venv/bin/python /opt/mychuannong/backup.py
UMask=0077
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/mychuannong /var/backups/mychuannong
SERVICE
cat > /etc/systemd/system/mychuannong-backup.timer <<'TIMER'
[Unit]
Description=Back up MyChuannong database daily

[Timer]
OnCalendar=*-*-* 04:15:00 Asia/Shanghai
Persistent=true
RandomizedDelaySec=300

[Install]
WantedBy=timers.target
TIMER
install -d -m 755 /etc/letsencrypt/renewal-hooks/deploy
cat > /etc/letsencrypt/renewal-hooks/deploy/mychuannong-nginx <<'HOOK'
#!/bin/sh
set -eu
if [ "${RENEWED_LINEAGE:-}" = /etc/letsencrypt/live/mychuannong ]; then
    /usr/sbin/nginx -t
    /bin/systemctl reload nginx
fi
HOOK
chmod 755 /etc/letsencrypt/renewal-hooks/deploy/mychuannong-nginx
cat > /etc/logrotate.d/mychuannong <<'LOGROTATE'
/var/log/mychuannong/*.jsonl {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
    su mychuannong mychuannong
}
LOGROTATE
systemctl daemon-reload
systemctl enable --now mychuannong-backup.timer
systemctl start mychuannong-backup.service
systemctl is-enabled mychuannong-backend.service mychuannong-backup.timer certbot.timer
systemctl list-timers mychuannong-backup.timer certbot.timer --no-pager
