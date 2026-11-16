import base64, copy, hashlib, http.cookiejar, json, sys, tempfile, threading, unittest
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request,build_opener,HTTPCookieProcessor,ProxyHandler

ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'Tools/PluginCommunity'))
from server import CommunityServer
from contracts import APIError,decode_package

class CommunityTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.server=CommunityServer(('127.0.0.1',0),Path(self.temp.name)/'community.sqlite3',seed=True)
        self.thread=threading.Thread(target=self.server.serve_forever,daemon=True);self.thread.start();self.base='http://127.0.0.1:'+str(self.server.server_port)
        self.author=build_opener(ProxyHandler({}),HTTPCookieProcessor(http.cookiejar.CookieJar()));self.reader=build_opener(ProxyHandler({}),HTTPCookieProcessor(http.cookiejar.CookieJar()))
    def tearDown(self):self.server.shutdown();self.server.server_close();self.thread.join();self.temp.cleanup()
    def call(self,path,method='GET',body=None,client=None,headers=None):
        raw=json.dumps(body,ensure_ascii=False).encode() if body is not None else None
        req=Request(self.base+path,data=raw,method=method,headers={'Content-Type':'application/json',**(headers or {})})
        try:
            with (client or build_opener(ProxyHandler({}))).open(req,timeout=10) as r:return r.status,json.loads(r.read()),dict(r.headers)
        except HTTPError as e:
            with e:return e.code,json.loads(e.read()),dict(e.headers)
    def register(self,client,uid):
        status,body,headers=self.call('/api/register','POST',{'id':uid,'name':'测试创作者 '+uid,'password':'qa-password-12345','roles':['colorist','developer']},client)
        self.assertEqual(status,200,body);self.assertIn('HttpOnly',headers['Set-Cookie']);return body['user']
    def package(self,kind='recipe',commercial=False):
        names={'recipe':'clear-portrait','lut':'warm-light','localAdjustment':'subject-light','aiTool':'portrait-assistant'}
        p=json.loads((ROOT/f'Resources/Plugins/Examples/studio.luma.{names[kind]}.lumaplugin').read_text());m=p['manifest'];m['id']='qa.creator.'+kind.lower();m['author']['id']='creator';m['author']['name']='测试作者'
        if commercial:m['license']={'type':'commercial','terms':'单席位商业授权；购买服务未连接。','priceCents':2900,'currency':'CNY'}
        return p
    def test_health_seed_search_real_zero_metrics(self):
        self.assertEqual(self.call('/health')[1]['service'],'luma-plugin-community');self.assertEqual(self.call('/ready')[1]['migration'],1)
        items=self.call('/api/plugins')[1]['items'];self.assertEqual(len(items),4);self.assertEqual({x['manifest']['kind'] for x in items},{'lut','recipe','localAdjustment','aiTool'})
        self.assertTrue(all(x['example'] and x['downloads']==0 and x['rating']['average'] is None and x['rating']['count']==0 for x in items))
        result=self.call('/api/plugins?q='+__import__('urllib.parse',fromlist=['quote']).quote('补光')+'&kind=localAdjustment')[1];self.assertEqual(result['total'],1)
        self.assertEqual(self.call('/api/config')[1]['payments'],'not_connected')
    def test_real_publish_search_rate_favorite_download_and_restart_persistence(self):
        self.register(self.author,'creator');self.register(self.reader,'reader')
        p=self.package();pid=p['manifest']['id'];status,body,_=self.call('/api/plugins','POST',p,self.author);self.assertEqual(status,201,body)
        self.assertEqual(self.call('/api/plugins?mine=1',client=self.author)[1]['total'],1)
        self.assertEqual(self.call('/api/plugins?q=qa.creator')[1]['total'],0) # search is title/author/tags, not an internal ID
        status,body,_=self.call(f'/api/plugins/{pid}/rating','PUT',{'score':5,'comment':'肤色自然，适合测试人像。'},self.reader);self.assertEqual(status,200,body);self.assertEqual(body['rating'],{'count':1,'average':5.0})
        self.call(f'/api/plugins/{pid}/rating','PUT',{'score':4,'comment':'更新反馈'},self.reader)
        item=self.call(f'/api/plugins/{pid}',client=self.reader)[1];self.assertEqual(item['rating'],{'count':1,'average':4.0})
        self.assertEqual(self.call(f'/api/plugins/{pid}/favorite','PUT',{'value':True},self.reader)[0],200)
        self.assertEqual(self.call('/api/plugins?favorites=1',client=self.reader)[1]['total'],1)
        status,package,headers=self.call(f'/api/plugins/{pid}/package?mode=install',client=self.reader);self.assertEqual(status,200);self.assertEqual(decode_package(json.dumps(package).encode())['manifest']['id'],pid);self.assertIn('x-package-sha256',{k.lower():v for k,v in headers.items()})
        from database import Database
        from catalog import Catalog
        persisted=Catalog(Database(Path(self.temp.name)/'community.sqlite3')).detail(pid,{'id':'reader'})
        self.assertTrue(persisted['favorite']);self.assertEqual(persisted['rating']['count'],1);self.assertEqual(persisted['downloads'],1)
    def test_author_identity_owner_version_immutability_and_semver(self):
        self.register(self.author,'creator');self.register(self.reader,'reader');p=self.package();pid=p['manifest']['id']
        self.assertEqual(self.call('/api/plugins','POST',p,self.reader)[0],403)
        self.assertEqual(self.call('/api/plugins','POST',p,self.author)[0],201)
        self.assertEqual(self.call('/api/plugins','POST',p,self.author)[0],409)
        p['manifest']['version']='0.9.0';self.assertEqual(self.call('/api/plugins','POST',p,self.author)[0],409)
        p['manifest']['version']='1.1.0';self.assertEqual(self.call('/api/plugins','POST',p,self.author)[0],201)
        self.assertEqual(len(self.call('/api/plugins/'+pid)[1]['versions']),2)
        self.assertEqual(self.call(f'/api/plugins/{pid}/rating','PUT',{'score':5,'comment':''},self.author)[0],403)
        hijack=copy.deepcopy(p);hijack['manifest']['author']['id']='reader';hijack['manifest']['version']='2.0.0';self.assertEqual(self.call('/api/plugins','POST',hijack,self.reader)[0],403)
    def test_commercial_trial_is_separate_from_purchase_and_author_download(self):
        self.register(self.author,'creator');self.register(self.reader,'reader');p=self.package(commercial=True);pid=p['manifest']['id']
        self.assertEqual(self.call('/api/plugins','POST',p,self.author)[0],201)
        status,body,_=self.call(f'/api/plugins/{pid}/package?mode=install',client=self.reader);self.assertEqual(status,403);self.assertEqual(body['error']['code'],'purchase_unavailable')
        self.assertEqual(self.call(f'/api/plugins/{pid}/package?mode=trial',client=self.reader)[0],200)
        self.assertEqual(self.call(f'/api/plugins/{pid}/package?mode=install',client=self.author)[0],200)
        self.assertIsNone(self.call('/api/authors/creator')[1]['earnings']['amount'])
        # A later free version must not grant download rights to a commercial old version.
        p['manifest']['version']='1.1.0';p['manifest']['license']={'type':'free','terms':'免费使用。'}
        self.assertEqual(self.call('/api/plugins','POST',p,self.author)[0],201)
        self.assertEqual(self.call(f'/api/plugins/{pid}/package?mode=install&version=1.0.0',client=self.reader)[0],403)
        self.assertEqual(self.call(f'/api/plugins/{pid}/package?mode=install&version=1.1.0',client=self.reader)[0],200)
    def test_invalid_packages_are_rejected_before_publish(self):
        for name in ['warm-light','clear-portrait','subject-light','portrait-assistant']:decode_package((ROOT/f'Resources/Plugins/Examples/studio.luma.{name}.lumaplugin').read_bytes())
        p=self.package('lut');p['assets'][0]['path']='../bad.cube'
        with self.assertRaises(APIError):decode_package(json.dumps(p).encode())
        p=self.package('lut');p['assets'][0]['data']=base64.b64encode(b'wrong').decode()
        with self.assertRaises(APIError):decode_package(json.dumps(p).encode())
        p=self.package();p['payload']['recipe']['global']['exposure']=99
        with self.assertRaises(APIError):decode_package(json.dumps(p).encode())
        p=self.package();p['payload']['groups']=['geometry']
        with self.assertRaises(APIError):decode_package(json.dumps(p).encode())
        p=self.package();p['payload']['recipe']['color']['curve']={'master':[{'x':0,'y':0},{'x':0,'y':1}]}
        with self.assertRaises(APIError):decode_package(json.dumps(p).encode())
        p=self.package();p['payload']['recipe']['lockedParameters']=['global','global']
        with self.assertRaises(APIError):decode_package(json.dumps(p).encode())
        p=self.package('aiTool');p['payload']['script']='exec'
        with self.assertRaises(APIError):decode_package(json.dumps(p).encode())
    def test_cookie_logout_cross_origin_host_validation_and_input_errors(self):
        self.register(self.author,'creator');self.assertEqual(self.call('/api/me',client=self.author)[1]['user']['id'],'creator')
        self.assertEqual(self.call('/api/plugins','POST',self.package(),self.author,{'Origin':'https://evil.example'})[0],403)
        self.assertEqual(self.call('/health',headers={'Host':'evil.example'})[0],403)
        self.assertEqual(self.call('/api/plugins?sort=bogus')[0],422)
        self.assertEqual(self.call('/api/plugins?q='+('a'*121))[0],422)
        self.assertEqual(self.call('/api/logout','POST',{},self.author)[0],200)
        self.assertIsNone(self.call('/api/me',client=self.author)[1]['user']);self.assertEqual(self.call('/api/plugins','POST',self.package(),self.author)[0],401)
        with self.server.db.connection() as db:
            row=db.execute('SELECT * FROM users WHERE id=?',('creator',)).fetchone();self.assertNotEqual(row['password'],b'qa-password-12345');self.assertEqual(len(row['salt']),16)
    def test_profile_update_preserves_published_package_and_session(self):
        self.register(self.author,'creator');p=self.package();pid=p['manifest']['id']
        self.assertEqual(self.call('/api/plugins','POST',p,self.author)[0],201)
        before=self.call(f'/api/plugins/{pid}/package')[1]
        body={'name':'摄影师新昵称','roles':['photographer'],'bio':'专注人像与自然光。'}
        self.assertEqual(self.call('/api/me','PUT',body)[0],401)
        status,result,_=self.call('/api/me','PUT',body,self.author);self.assertEqual(status,200,result)
        self.assertEqual(self.call('/api/me',client=self.author)[1]['user']['name'],body['name'])
        self.assertEqual(self.call('/api/authors/creator')[1]['bio'],body['bio'])
        from urllib.parse import quote
        self.assertEqual(self.call('/api/plugins?q='+quote(body['name']))[1]['total'],1)
        self.assertEqual(self.call(f'/api/plugins/{pid}/package')[1],before)
        for bad in [dict(body,id='reader'),dict(body,roles=[]),dict(body,roles=['developer','developer']),dict(body,bio='x'*601)]:
            self.assertEqual(self.call('/api/me','PUT',bad,self.author)[0],422)

    def test_follow_feed_idempotence_unfollow_and_database_restart(self):
        self.register(self.author,'creator');self.register(self.reader,'reader');p=self.package()
        self.call('/api/plugins','POST',p,self.author)
        self.assertEqual(self.call('/api/plugins?following=1')[0],401)
        self.assertEqual(self.call('/api/authors/creator/follow','PUT',{'value':True})[0],401)
        self.assertEqual(self.call('/api/authors/reader/follow','PUT',{'value':True},self.reader)[0],422)
        self.assertEqual(self.call('/api/authors/missing/follow','PUT',{'value':True},self.reader)[0],404)
        for _ in range(2):
            status,result,_=self.call('/api/authors/creator/follow','PUT',{'value':True},self.reader)
            self.assertEqual(status,200);self.assertEqual(result['followers'],1)
        self.assertEqual(self.call('/api/plugins?following=1',client=self.reader)[1]['total'],1)
        from database import Database
        from catalog import Catalog
        restored=Catalog(Database(Path(self.temp.name)/'community.sqlite3')).author('creator',{'id':'reader'})
        self.assertTrue(restored['following']);self.assertEqual(restored['followers'],1)
        self.call('/api/authors/creator/follow','PUT',{'value':False},self.reader)
        self.assertEqual(self.call('/api/plugins?following=1',client=self.reader)[1]['total'],0)

    def test_pagination_reaches_beyond_one_hundred_and_author_filter(self):
        self.register(self.author,'creator')
        for n in range(105):
            p=self.package('aiTool');p['manifest']['id']=f'qa.page.n{n}'
            self.server.catalog.publish(json.dumps(p).encode(),{'id':'creator'})
        seen=[]
        for offset in range(0,105,24):
            status,result,_=self.call(f'/api/plugins?author=creator&limit=24&offset={offset}')
            self.assertEqual(status,200);self.assertEqual(result['total'],105)
            self.assertEqual(result['hasMore'],offset+24<105)
            seen.extend(i['manifest']['id'] for i in result['items'])
        self.assertEqual(len(seen),105);self.assertEqual(len(set(seen)),105)
        profile=self.call('/api/authors/creator')[1];self.assertEqual(profile['pluginCount'],105);self.assertEqual(len(profile['plugins']),24)
        for query in ['offset=-1','limit=0','limit=101','offset=nan','offset=%C2%B2','offset='+('9'*100)]:
            self.assertEqual(self.call('/api/plugins?'+query)[0],422)

    def test_unauthorized_and_review_validation_and_report_queue(self):
        pid='studio.luma.clear-portrait';self.assertEqual(self.call(f'/api/plugins/{pid}/favorite','PUT',{'value':True})[0],401)
        self.register(self.reader,'reader')
        self.assertEqual(self.call(f'/api/plugins/{pid}/rating','PUT',{'score':6,'comment':''},self.reader)[0],422)
        self.assertEqual(self.call(f'/api/plugins/{pid}/favorite','PUT',{'value':'yes'},self.reader)[0],422)
        self.assertEqual(self.call(f'/api/plugins/{pid}/report','POST',{'reason':'许可信息需要核对'},self.reader)[1]['status'],'pending')
        with self.server.db.connection() as db:self.assertEqual(db.execute('SELECT count(*) FROM reports').fetchone()[0],1)

if __name__=='__main__':unittest.main()
