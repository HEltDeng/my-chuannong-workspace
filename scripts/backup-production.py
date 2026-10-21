"""Consistent daily database backup, with the backend's integrity manifest."""
import sys
from pathlib import Path

sys.path.insert(0, '/opt/mychuannong/current')
from scripts.database_tools import backup_database

report = backup_database(
    Path('/var/lib/mychuannong/my-chuannong.db'),
    Path('/var/backups/mychuannong'),
    retention_days=14,
)
print('MyChuannong database backup completed with integrity verification.')
