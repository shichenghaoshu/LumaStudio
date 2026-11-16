import contextlib, json, sqlite3, time
from pathlib import Path

class Database:
    def __init__(self,path):
        self.path=Path(path);self.path.parent.mkdir(parents=True,exist_ok=True)
        with self.connection() as db:
            db.executescript('''
            PRAGMA journal_mode=WAL;
            CREATE TABLE IF NOT EXISTS migrations(version INTEGER PRIMARY KEY, applied_at INTEGER NOT NULL);
            CREATE TABLE IF NOT EXISTS users(id TEXT PRIMARY KEY,name TEXT NOT NULL,roles TEXT NOT NULL,bio TEXT NOT NULL DEFAULT '',salt BLOB,password BLOB,created_at INTEGER NOT NULL);
            CREATE TABLE IF NOT EXISTS sessions(hash TEXT PRIMARY KEY,user_id TEXT NOT NULL REFERENCES users(id),expires_at INTEGER NOT NULL);
            CREATE TABLE IF NOT EXISTS plugins(id TEXT PRIMARY KEY,owner_id TEXT NOT NULL REFERENCES users(id),latest TEXT NOT NULL,manifest TEXT NOT NULL,created_at INTEGER NOT NULL,updated_at INTEGER NOT NULL,example INTEGER NOT NULL DEFAULT 0);
            CREATE TABLE IF NOT EXISTS versions(plugin_id TEXT NOT NULL REFERENCES plugins(id),version TEXT NOT NULL,sha256 TEXT NOT NULL,package BLOB NOT NULL,created_at INTEGER NOT NULL,PRIMARY KEY(plugin_id,version));
            CREATE TABLE IF NOT EXISTS ratings(plugin_id TEXT NOT NULL REFERENCES plugins(id),user_id TEXT NOT NULL REFERENCES users(id),score INTEGER NOT NULL CHECK(score BETWEEN 1 AND 5),comment TEXT NOT NULL,updated_at INTEGER NOT NULL,PRIMARY KEY(plugin_id,user_id));
            CREATE TABLE IF NOT EXISTS favorites(plugin_id TEXT NOT NULL REFERENCES plugins(id),user_id TEXT NOT NULL REFERENCES users(id),created_at INTEGER NOT NULL,PRIMARY KEY(plugin_id,user_id));
            CREATE TABLE IF NOT EXISTS events(id INTEGER PRIMARY KEY,plugin_id TEXT NOT NULL REFERENCES plugins(id),user_id TEXT,event TEXT NOT NULL,created_at INTEGER NOT NULL);
            CREATE TABLE IF NOT EXISTS reports(id INTEGER PRIMARY KEY,plugin_id TEXT NOT NULL REFERENCES plugins(id),user_id TEXT NOT NULL REFERENCES users(id),reason TEXT NOT NULL,created_at INTEGER NOT NULL,status TEXT NOT NULL DEFAULT 'pending');
            CREATE INDEX IF NOT EXISTS events_plugin ON events(plugin_id,event);
            CREATE INDEX IF NOT EXISTS ratings_plugin ON ratings(plugin_id);
            CREATE INDEX IF NOT EXISTS favorites_user ON favorites(user_id,plugin_id);
            INSERT OR IGNORE INTO migrations VALUES(1,strftime('%s','now'));
            ''')
    @contextlib.contextmanager
    def connection(self):
        db=sqlite3.connect(self.path,timeout=10);db.row_factory=sqlite3.Row
        db.create_function('casefold',1,lambda s:(s or '').casefold(),deterministic=True)
        db.execute('PRAGMA foreign_keys=ON');db.execute('PRAGMA busy_timeout=10000')
        try:
            with db: yield db
        finally: db.close()
    def ready(self):
        with self.connection() as db: return db.execute('SELECT max(version) FROM migrations').fetchone()[0]==1
