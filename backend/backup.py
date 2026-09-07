"""Make a consistent SQLite backup, including committed WAL data."""
import argparse
import os
import sqlite3
from pathlib import Path
parser = argparse.ArgumentParser()
parser.add_argument('destination')
parser.add_argument('--database', default=str(Path(__file__).parent / 'data/aurum.sqlite3'))
args = parser.parse_args()
target = Path(args.destination)
if target.exists():
    parser.error('Choose a destination that does not already exist.')
with sqlite3.connect(args.database) as source, sqlite3.connect(target) as destination:
    source.backup(destination)
os.chmod(target, 0o600)
print('Backup completed.')
