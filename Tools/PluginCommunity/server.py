#!/usr/bin/env python3
"""Local creator community: python3 Tools/PluginCommunity/server.py --seed-examples."""
import argparse, collections, hashlib, ipaddress, json, logging, os, re, signal, threading, time, uuid
from http import HTTPStatus
from http.cookies import SimpleCookie
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit
from accounts import Accounts, SESSION_SECONDS
from catalog import Catalog
from contracts import APIError, MAX_BYTES, require
from database import Database

STATIC=Path(__file__).parent/'static'
class CommunityServer(ThreadingHTTPServer):
    daemon_threads=True
    def __init__(self,address,db,seed=False,public_origin=None):
        if public_origin:
            origin=urlsplit(public_origin)
            if origin.scheme!='https' or not origin.hostname or origin.username or origin.password or origin.path not in ['', '/'] or origin.query or origin.fragment:
                raise ValueError('Public community requires an HTTPS origin without a path or credentials')
            public_origin='https://'+origin.netloc
        self.public_origin=public_origin
        self.db=Database(db);self.accounts=Accounts(self.db);self.catalog=Catalog(self.db)
        if seed:self.catalog.seed()
        self.rates=collections.defaultdict(list);self.rate_lock=threading.Lock()
        super().__init__(address,Handler)
    def limit(self,key,count,period):
        now=time.monotonic()
        with self.rate_lock:
            if len(self.rates)>10000:
                self.rates=collections.defaultdict(list,{k:v for k,v in self.rates.items() if v and now-v[-1]<3600})
            events=[t for t in self.rates[key] if now-t<period]
            require(len(events)<count,'操作较频繁，请稍后重试','rate_limited',429)
            events.append(now);self.rates[key]=events

class Handler(BaseHTTPRequestHandler):
    server_version='LumaCommunity/1'
    def log_message(self,*args):pass
    def do_GET(self):self.dispatch('GET')
    def do_POST(self):self.dispatch('POST')
    def do_PUT(self):self.dispatch('PUT')
    def do_OPTIONS(self):self.dispatch('OPTIONS')
    def token(self):
        auth=self.headers.get('Authorization','')
        if auth.startswith('Bearer '):return auth[7:]
        try:
            c=SimpleCookie();c.load(self.headers.get('Cookie',''));return c['luma_session'].value if 'luma_session' in c else ''
        except Exception:return ''
    def body(self,raw=False):
        value=self.headers.get('Content-Length','')
        require(value.isdigit() and 0<int(value)<=MAX_BYTES,'请求内容为空或超过 12 MB','request_size',413)
        require(self.headers.get('Content-Type','').split(';')[0]=='application/json','请求需使用 application/json','content_type',415)
        data=self.rfile.read(int(value));require(len(data)==int(value),'请求未传输完整','incomplete_body',400)
        if raw:return data
        try:return json.loads(data)
        except (ValueError,UnicodeDecodeError,RecursionError):raise APIError(400,'invalid_json','JSON 格式无效')
    def respond(self,status,payload,kind='application/json; charset=utf-8',headers=None):
        raw=payload if isinstance(payload,bytes) else json.dumps(payload,ensure_ascii=False,allow_nan=False).encode()
        self.send_response(status);self.send_header('Content-Type',kind);self.send_header('Content-Length',str(len(raw)))
        self.send_header('Cache-Control','no-store');self.send_header('X-Content-Type-Options','nosniff')
        self.send_header('Referrer-Policy','no-referrer');self.send_header('X-Request-ID',self.request_id)
        self.send_header('Content-Security-Policy',"default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'")
        for k,v in (headers or {}).items():self.send_header(k,v)
        self.end_headers();self.wfile.write(raw)
    def cookie(self,token):return {'Set-Cookie':f'luma_session={token}; Path=/; HttpOnly; SameSite=Strict; Max-Age={SESSION_SECONDS if token else 0}'+('; Secure' if self.server.public_origin else '')}
    def dispatch(self,method):
        self.connection.settimeout(20);self.request_id=uuid.uuid4().hex;started=time.monotonic();status=500
        path=urlsplit(self.path).path
        try:
            port=self.server.server_port
            allowed={f'127.0.0.1:{port}',f'localhost:{port}'}
            origins={'http://'+v for v in allowed}
            if self.server.public_origin:
                allowed.add(urlsplit(self.server.public_origin).netloc);origins={self.server.public_origin}
            require(self.headers.get('Host') in allowed,'社区访问地址不匹配','invalid_host',403)
            origin=self.headers.get('Origin')
            require(origin is None or origin in origins,'仅允许同源请求','invalid_origin',403)
            require(method!='OPTIONS','仅支持同源访问','invalid_origin',403)
            q=parse_qs(urlsplit(self.path).query,keep_blank_values=True)
            get=lambda key,default='':q.get(key,[default])[0]
            token=self.token();user=self.server.accounts.session(token)
            client=self.client_address[0]
            # Public mode runs behind the packaged loopback-only nginx proxy,
            # which overwrites this header. Never publish the backend port.
            if self.server.public_origin:
                try:client=str(ipaddress.ip_address(self.headers.get('X-Real-IP',client)))
                except ValueError:pass
            auth=lambda:self.server.accounts.session(token,required=True)
            catalog=self.server.catalog
            headers={};kind='application/json; charset=utf-8';result=None;status=200
            if method=='GET' and path=='/health':result={'status':'ok','service':'luma-plugin-community','protocol':1}
            elif method=='GET' and path=='/ready':
                require(self.server.db.ready(),'数据库尚未就绪','not_ready',503);result={'status':'ready','migration':1}
            elif method=='GET' and path=='/api/config':result={'schemaVersion':1,'localOnly':not bool(self.server.public_origin),'payments':'not_connected','payouts':'not_connected','maxPackageBytes':MAX_BYTES,'host':'macOS','runtime':'declarative-v1'}
            elif method=='GET' and path=='/api/me':result={'user':user}
            elif method=='PUT' and path=='/api/me':
                u=auth();result=self.server.accounts.update_profile(self.body(),u)
            elif method=='POST' and path in ['/api/register','/api/login']:
                self.server.limit(('auth',client),12,60)
                user,newtoken=(self.server.accounts.register if path.endswith('register') else self.server.accounts.login)(self.body());headers=self.cookie(newtoken);result={'user':user}
            elif method=='POST' and path=='/api/logout':self.server.accounts.logout(token);headers=self.cookie('');result={'ok':True}
            elif method=='GET' and path=='/api/plugins':
                require(re.fullmatch(r'[0-9]{1,7}',get('offset','0')) and re.fullmatch(r'[0-9]{1,3}',get('limit','24')),'分页参数无效')
                result=catalog.search(get('q'),get('kind'),get('sort','recent'),user,get('favorites')=='1',get('mine')=='1',get('following')=='1',int(get('offset','0')),int(get('limit','24')),get('author'))
            elif method=='POST' and path=='/api/plugins':
                u=auth();self.server.limit(('publish',u['id']),30,3600);result=catalog.publish(self.body(raw=True),u);status=201
            elif method=='GET' and re.fullmatch(r'/api/authors/[a-z][a-z0-9_-]{2,39}',path):result=catalog.author(path.split('/')[-1],user)
            elif method=='PUT' and re.fullmatch(r'/api/authors/[a-z][a-z0-9_-]{2,39}/follow',path):
                u=auth();result=catalog.follow(path.split('/')[-2],self.body(),u)
            elif re.fullmatch(r'/api/plugins/[a-z0-9.-]+(?:/(?:package|favorite|rating|report))?',path):
                parts=path.split('/');pid=parts[3];action=parts[4] if len(parts)>4 else ''
                if method=='GET' and not action:result=catalog.detail(pid,user)
                elif method=='GET' and action=='package':
                    self.server.limit(('package',client),120,60)
                    result,sha=catalog.package(pid,get('version'),get('mode','download'),user)
                    kind='application/json; charset=utf-8';headers={'X-Package-SHA256':sha,'Content-Disposition':f'attachment; filename="{pid}.lumaplugin"'}
                elif method=='PUT' and action=='favorite':result=catalog.favorite(pid,self.body(),auth())
                elif method=='PUT' and action=='rating':result=catalog.rate(pid,self.body(),auth())
                elif method=='POST' and action=='report':result=catalog.report(pid,self.body(),auth())
                else:raise APIError(405,'method_not_allowed','不支持此操作')
            elif method=='GET' and path in ['/','/index.html','/app.js','/style.css']:
                file=STATIC/('index.html' if path=='/' else path[1:]);result=file.read_bytes()
                kind={'.html':'text/html; charset=utf-8','.js':'text/javascript; charset=utf-8','.css':'text/css; charset=utf-8'}[file.suffix]
            else:raise APIError(404,'not_found','页面或接口不存在')
            self.respond(status,result,kind,headers)
        except APIError as error:
            status=error.status;self.respond(status,{'error':{'code':error.code,'message':error.message,'requestId':self.request_id}})
        except (BrokenPipeError,ConnectionResetError,TimeoutError):status=408
        except Exception as error:
            status=500;logging.error(json.dumps({'event':'internal_error','requestId':self.request_id,'type':type(error).__name__}))
            self.respond(500,{'error':{'code':'internal_error','message':'服务处理失败，请稍后重试','requestId':self.request_id}})
        finally:
            # Never log cookies, authorization, body, query strings or photo paths.
            logging.info(json.dumps({'event':'request','requestId':self.request_id,'method':method,'route':path[:180],'status':status,'milliseconds':round((time.monotonic()-started)*1000)}))

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port',type=int,default=int(os.environ.get('LUMA_COMMUNITY_PORT','8791')))
    parser.add_argument('--data',type=Path,default=Path(os.environ.get('LUMA_COMMUNITY_DATA',str(Path.home()/'Library/Application Support/LumaStudio/Community/community.sqlite3'))))
    parser.add_argument('--seed-examples',action='store_true');parser.add_argument('--parent-pid',type=int);args=parser.parse_args()
    if not 1024<=args.port<=65535:parser.error('端口需为 1024–65535')
    logging.basicConfig(level=logging.INFO,format='%(message)s')
    bind=os.environ.get('LUMA_COMMUNITY_BIND','127.0.0.1')
    public_origin=os.environ.get('LUMA_COMMUNITY_PUBLIC_ORIGIN')
    if bind!='127.0.0.1' and not public_origin:parser.error('非回环监听必须配置 HTTPS 公网地址并置于反向代理后')
    server=CommunityServer((bind,args.port),args.data,args.seed_examples,public_origin)
    def stop(*_):threading.Thread(target=server.shutdown,daemon=True).start()
    signal.signal(signal.SIGINT,stop);signal.signal(signal.SIGTERM,stop)
    if args.parent_pid:
        def watch_parent():
            while True:
                time.sleep(2)
                try:os.kill(args.parent_pid,0)
                except ProcessLookupError:server.shutdown();return
        threading.Thread(target=watch_parent,daemon=True).start()
    print(f'LumaStudio 创作中心: http://127.0.0.1:{server.server_port}',flush=True)
    try:server.serve_forever(poll_interval=.25)
    finally:server.server_close()
if __name__=='__main__':main()
