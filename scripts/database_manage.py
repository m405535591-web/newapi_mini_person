"""由数据库管理.bat 在服务停止并确认后调用。"""

import argparse
from contextlib import closing
from datetime import datetime
from pathlib import Path
import sqlite3


def clear_checkins(root: Path) -> tuple[int, Path]:
    database = root / 'data' / 'new-api.db'
    # mode=rw prevents accidentally creating an empty database.
    with closing(sqlite3.connect(database.resolve().as_uri() + '?mode=rw', uri=True)) as connection:
        connection.execute('SELECT id, user_id, checkin_date FROM checkins LIMIT 0')
        backup_dir = root / 'backups' / ('checkins-reset-' + datetime.now().strftime('%Y%m%d-%H%M%S-%f'))
        backup_dir.mkdir(parents=True, exist_ok=False)
        backup_path = backup_dir / 'new-api.db'
        with closing(sqlite3.connect(backup_path)) as backup:
            connection.backup(backup)
            if backup.execute('PRAGMA quick_check').fetchall() != [('ok',)]:
                raise RuntimeError('备份完整性检查失败，取消删除。')
        with connection:
            deleted = connection.execute('DELETE FROM checkins').rowcount
        return deleted, backup_path


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    args = parser.parse_args()
    count, backup = clear_checkins(args.root)
    print(f'数据库备份：{backup}')
    print(f'已删除 {count} 条签到记录；已发放额度未变更。')
