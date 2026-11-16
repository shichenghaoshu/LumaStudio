import hashlib, hmac, json, secrets, time
from contracts import APIError, USER, keys, require, text

SESSION_SECONDS=30*86400
class Accounts:
    def __init__(self,db): self.db=db
    @staticmethod
    def profile(row): return {k:json.loads(row[k]) if k=='roles' else row[k] for k in ['id','name','roles','bio']}
    def session(self,token,required=False):
        if token:
            with self.db.connection() as db:
                row=db.execute('SELECT u.* FROM sessions s JOIN users u ON u.id=s.user_id WHERE s.hash=? AND s.expires_at>?',(hashlib.sha256(token.encode()).hexdigest(),int(time.time()))).fetchone()
            if row: return self.profile(row)
        if required: raise APIError(401,'login_required','请先登录创作者账号')
        return None
    def issue(self,db,user):
        token=secrets.token_urlsafe(32);now=int(time.time())
        db.execute('DELETE FROM sessions WHERE expires_at<=?',(now,))
        db.execute('INSERT INTO sessions VALUES(?,?,?)',(hashlib.sha256(token.encode()).hexdigest(),user,now+SESSION_SECONDS))
        return token
    def register(self,body):
        keys(body,{'id','name','password','roles','bio'},{'id','name','password','roles'})
        uid=body['id'];password=body['password']
        require(isinstance(uid,str) and USER.fullmatch(uid) and uid not in ['lumastudio','admin','system'],'账号需为 3–40 位小写字母、数字或下划线，不能使用保留名','invalid_account',422)
        require(text(body['name'],80) and isinstance(password,str) and 10<=len(password)<=256,'昵称需填写，密码需为 10–256 位','invalid_account',422)
        roles=body['roles'];require(isinstance(roles,list) and 1<=len(roles)<=3 and all(r in ['photographer','colorist','developer'] for r in roles),'请选择创作者角色')
        require(isinstance(body.get('bio',''),str) and len(body.get('bio',''))<=600,'个人介绍过长')
        salt=secrets.token_bytes(16);hashed=hashlib.pbkdf2_hmac('sha256',password.encode(),salt,600000)
        with self.db.connection() as db:
            db.execute('BEGIN IMMEDIATE')
            require(db.execute('SELECT 1 FROM users WHERE id=?',(uid,)).fetchone() is None,'账号已存在','account_exists',409)
            db.execute('INSERT INTO users VALUES(?,?,?,?,?,?,?)',(uid,body['name'],json.dumps(roles),body.get('bio',''),salt,hashed,int(time.time())))
            token=self.issue(db,uid);user=self.profile(db.execute('SELECT * FROM users WHERE id=?',(uid,)).fetchone())
        return user,token
    def login(self,body):
        keys(body,{'id','password'},{'id','password'})
        require(isinstance(body['id'],str) and len(body['id'])<=40 and isinstance(body['password'],str) and len(body['password'])<=256,'登录信息格式错误','invalid_account',422)
        with self.db.connection() as db:
            row=db.execute('SELECT * FROM users WHERE id=?',(body['id'],)).fetchone()
            # Equal-cost hash for missing/disabled accounts as well.
            expected=row['password'] if row and row['password'] else bytes(32)
            actual=hashlib.pbkdf2_hmac('sha256',body['password'].encode(),row['salt'] if row and row['salt'] else bytes(16),600000)
            require(bool(row and row['password']) and hmac.compare_digest(actual,expected),'账号或密码错误','invalid_login',401)
            return self.profile(row),self.issue(db,row['id'])
    def logout(self,token):
        if token:
            with self.db.connection() as db: db.execute('DELETE FROM sessions WHERE hash=?',(hashlib.sha256(token.encode()).hexdigest(),))
    def update_profile(self,body,user):
        keys(body,{'name','roles','bio'},{'name','roles','bio'})
        require(text(body['name'],80),'昵称需为 1–80 字')
        roles=body['roles']
        require(isinstance(roles,list) and 1<=len(roles)<=3 and all(isinstance(r,str) and r in ['photographer','colorist','developer'] for r in roles) and len(set(roles))==len(roles),'请选择不重复的创作者身份')
        require(isinstance(body['bio'],str) and len(body['bio'])<=600,'个人介绍最多 600 字')
        with self.db.connection() as db:
            db.execute('UPDATE users SET name=?,roles=?,bio=? WHERE id=?',(body['name'].strip(),json.dumps(roles),body['bio'],user['id']))
            return {'user':self.profile(db.execute('SELECT * FROM users WHERE id=?',(user['id'],)).fetchone())}
