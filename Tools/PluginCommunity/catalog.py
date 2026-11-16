import hashlib, json, time
from contracts import APIError, ROOT, decode_package, integer, keys, require, text

class Catalog:
    def __init__(self,db): self.db=db
    def seed(self):
        with self.db.connection() as db:
            db.execute('INSERT OR IGNORE INTO users(id,name,roles,bio,created_at) VALUES(?,?,?,?,?)',('lumastudio','LumaStudio 示例作者',json.dumps(['photographer','colorist','developer']),'四类原创示例，可查看协议并改编。',int(time.time())))
        for path in sorted((ROOT/'Resources/Plugins/Examples').glob('*.lumaplugin')):
            raw=path.read_bytes();p=decode_package(raw)
            with self.db.connection() as db: exists=db.execute('SELECT 1 FROM plugins WHERE id=?',(p['manifest']['id'],)).fetchone()
            if not exists: self.publish(raw,{'id':'lumastudio'},example=True)
    def publish(self,raw,user,example=False):
        p=decode_package(raw);m=p['manifest'];now=int(time.time());uid=user['id']
        require(m['author']['id']==uid,'插件作者 ID 必须与当前账号一致','author_mismatch',403)
        with self.db.connection() as db:
            db.execute('BEGIN IMMEDIATE')
            existing=db.execute('SELECT * FROM plugins WHERE id=?',(m['id'],)).fetchone()
            if existing:
                require(existing['owner_id']==uid,'不能更新他人的插件','not_owner',403)
                require(db.execute('SELECT 1 FROM versions WHERE plugin_id=? AND version=?',(m['id'],m['version'])).fetchone() is None,'该版本已经发布，请增加版本号','version_exists',409)
                require(tuple(map(int,m['version'].split('.')))>tuple(map(int,existing['latest'].split('.'))),'新版本号必须高于当前版本','version_order',409)
            used=db.execute('SELECT COALESCE(sum(length(v.package)),0) FROM versions v JOIN plugins p ON p.id=v.plugin_id WHERE p.owner_id=?',(uid,)).fetchone()[0]
            require(used+len(raw)<=200*1024*1024,'本地社区每位作者的包总大小上限为 200 MB','quota_exceeded',413)
            encoded=json.dumps(m,ensure_ascii=False)
            if existing: db.execute('UPDATE plugins SET latest=?,manifest=?,updated_at=? WHERE id=?',(m['version'],encoded,now,m['id']))
            else: db.execute('INSERT INTO plugins VALUES(?,?,?,?,?,?,?)',(m['id'],uid,m['version'],encoded,now,now,int(example)))
            db.execute('INSERT INTO versions VALUES(?,?,?,?,?)',(m['id'],m['version'],hashlib.sha256(raw).hexdigest(),raw,now))
        return self.detail(m['id'],user)
    def _item(self,db,row,user):
        uid=user['id'] if user else ''
        rating=db.execute('SELECT count(*),avg(score) FROM ratings WHERE plugin_id=?',(row['id'],)).fetchone()
        counts={r['event']:r['n'] for r in db.execute('SELECT event,count(*) n FROM events WHERE plugin_id=? GROUP BY event',(row['id'],))}
        own=db.execute('SELECT score,comment FROM ratings WHERE plugin_id=? AND user_id=?',(row['id'],uid)).fetchone()
        return {'manifest':json.loads(row['manifest']),'example':bool(row['example']),'updatedAt':row['updated_at'],'rating':{'count':rating[0],'average':round(rating[1],2) if rating[1] else None},'downloads':counts.get('download',0),'trials':counts.get('trial',0),'favorites':db.execute('SELECT count(*) FROM favorites WHERE plugin_id=?',(row['id'],)).fetchone()[0],'favorite':bool(db.execute('SELECT 1 FROM favorites WHERE plugin_id=? AND user_id=?',(row['id'],uid)).fetchone()),'myRating':dict(own) if own else None,'canInstall':json.loads(row['manifest'])['license']['type']!='commercial' or row['owner_id']==uid,'owner':row['owner_id']==uid}
    def search(self,q,kind,sort,user,favorites=False,mine=False):
        require(len(q)<=120 and kind in ['', 'lut','recipe','localAdjustment','aiTool'] and sort in ['recent','rating','downloads'],'搜索参数无效')
        if favorites or mine: require(user is not None,'请先登录','login_required',401)
        conditions=[];params=[]
        if q:
            conditions.append("instr(casefold(json_extract(manifest,'$.name') || ' ' || json_extract(manifest,'$.summary') || ' ' || json_extract(manifest,'$.author.name') || ' ' || owner_id || ' ' || json_extract(manifest,'$.tags')),?)>0");params.append(q.casefold())
        if kind:conditions.append("json_extract(manifest,'$.kind')=?");params.append(kind)
        if mine:conditions.append('owner_id=?');params.append(user['id'])
        if favorites:conditions.append('EXISTS(SELECT 1 FROM favorites f WHERE f.plugin_id=p.id AND f.user_id=?)');params.append(user['id'])
        where=' WHERE '+' AND '.join(conditions) if conditions else ''
        order={'recent':'updated_at DESC,id','rating':'COALESCE((SELECT avg(score) FROM ratings r WHERE r.plugin_id=p.id),0) DESC,updated_at DESC','downloads':"(SELECT count(*) FROM events e WHERE e.plugin_id=p.id AND e.event='download') DESC,updated_at DESC"}[sort]
        with self.db.connection() as db:
            total=db.execute('SELECT count(*) FROM plugins p'+where,params).fetchone()[0]
            rows=db.execute('SELECT * FROM plugins p'+where+' ORDER BY '+order+' LIMIT 100',params).fetchall()
            return {'items':[self._item(db,row,user) for row in rows],'total':total}
    def detail(self,pid,user):
        with self.db.connection() as db:
            row=db.execute('SELECT * FROM plugins WHERE id=?',(pid,)).fetchone();require(row is not None,'插件不存在','not_found',404)
            item=self._item(db,row,user)
            item['versions']=[dict(r) for r in db.execute('SELECT version,sha256,created_at FROM versions WHERE plugin_id=? ORDER BY created_at DESC,version DESC',(pid,))]
            item['reviews']=[dict(r) for r in db.execute('SELECT r.user_id,u.name,r.score,r.comment,r.updated_at FROM ratings r JOIN users u ON u.id=r.user_id WHERE plugin_id=? ORDER BY r.updated_at DESC LIMIT 50',(pid,))]
            return item
    def package(self,pid,version,mode,user):
        require(mode in ['trial','install','download'],'下载模式无效')
        with self.db.connection() as db:
            row=db.execute('SELECT * FROM plugins WHERE id=?',(pid,)).fetchone();require(row is not None,'插件不存在','not_found',404)
            v=db.execute('SELECT * FROM versions WHERE plugin_id=? AND version=?',(pid,version or row['latest'])).fetchone();require(v is not None,'版本不存在','not_found',404)
            # Entitlement follows the requested immutable version, never the latest listing.
            m=json.loads(v['package'])['manifest']
            if mode!='trial' and m['license']['type']=='commercial':
                require(user and row['owner_id']==user['id'],'购买尚未开放。商业插件目前仅作者可安装；可以在 Mac 中试用预览。','purchase_unavailable',403)
            db.execute('INSERT INTO events(plugin_id,user_id,event,created_at) VALUES(?,?,?,?)',(pid,user['id'] if user else None,'trial' if mode=='trial' else 'download',int(time.time())))
            return bytes(v['package']),v['sha256']
    def favorite(self,pid,body,user):
        keys(body,{'value'},{'value'});require(type(body['value']) is bool,'收藏状态需为布尔值')
        self.detail(pid,user)
        with self.db.connection() as db:
            if body['value']: db.execute('INSERT OR IGNORE INTO favorites VALUES(?,?,?)',(pid,user['id'],int(time.time())))
            else: db.execute('DELETE FROM favorites WHERE plugin_id=? AND user_id=?',(pid,user['id']))
        return self.detail(pid,user)
    def rate(self,pid,body,user):
        keys(body,{'score','comment'},{'score','comment'});require(integer(body['score']) and 1<=body['score']<=5 and isinstance(body['comment'],str) and len(body['comment'])<=600,'评分需为 1–5，评论最多 600 字')
        item=self.detail(pid,user);require(not item['owner'],'作者不能给自己的作品评分','self_rating',403)
        with self.db.connection() as db:
            db.execute('INSERT INTO ratings VALUES(?,?,?,?,?) ON CONFLICT(plugin_id,user_id) DO UPDATE SET score=excluded.score,comment=excluded.comment,updated_at=excluded.updated_at',(pid,user['id'],body['score'],body['comment'],int(time.time())))
        return self.detail(pid,user)
    def report(self,pid,body,user):
        keys(body,{'reason'},{'reason'});require(text(body['reason'],1000),'请填写具体问题');self.detail(pid,user)
        with self.db.connection() as db: db.execute('INSERT INTO reports(plugin_id,user_id,reason,created_at) VALUES(?,?,?,?)',(pid,user['id'],body['reason'],int(time.time())))
        return {'status':'pending','message':'已记录到本地服务，等待社区管理员审核'}
    def author(self,uid,user):
        with self.db.connection() as db:
            r=db.execute('SELECT id,name,roles,bio FROM users WHERE id=?',(uid,)).fetchone();require(r is not None,'作者不存在','not_found',404)
            profile=dict(r);profile['roles']=json.loads(profile['roles'])
            rows=db.execute('SELECT * FROM plugins WHERE owner_id=? ORDER BY updated_at DESC',(uid,)).fetchall()
            profile['plugins']=[self._item(db,row,user) for row in rows]
            profile['earnings']={'status':'not_connected','currency':'CNY','amount':None};return profile
