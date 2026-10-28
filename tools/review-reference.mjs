/** Read-only reference review. All HTTP and storage are mocked; no secrets are used.
 * node tools/review-reference.mjs <cloudflare-directory>
 * Confirmed findings reproduce defects; they are not a production-readiness pass.
 */
import assert from 'node:assert/strict';
import {readFileSync,existsSync} from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {createRequire} from 'node:module';
import {webcrypto} from 'node:crypto';
const reference=path.resolve(process.argv[2]||'D:/work/project/vibe-coding/zcode/mobile/cloudflare');
const root=path.join(reference,'worker','src');
const ts=createRequire(path.join(reference,'worker','package.json'))('typescript');
const results=[];
function loader(fetchImpl=async()=>{throw Error('Unexpected network request');}){
  const context=vm.createContext({URL,URLSearchParams,Request,Response,Headers,FormData,Blob,File,
    TextEncoder,TextDecoder,Uint8Array,ArrayBuffer,ReadableStream,crypto:webcrypto,btoa,atob,console,fetch:fetchImpl});
  const cache=new Map();
  function load(relative){
    const filename=path.resolve(root,relative);
    if(!filename.startsWith(root+path.sep))throw Error('Import outside source root');
    if(cache.has(filename))return cache.get(filename).exports;
    const module={exports:{}};cache.set(filename,module);
    const code=ts.transpileModule(readFileSync(filename,'utf8'),{fileName:filename,
      compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText;
    const localRequire=name=>{
      if(!name.startsWith('.'))throw Error('Unexpected external import: '+name);
      let target=path.resolve(path.dirname(filename),name);
      if(!existsSync(target))target+='.ts';
      return load(path.relative(root,target));
    };
    vm.runInContext('(function(require,module,exports){'+code+'\n})',context,{filename})(localRequire,module,module.exports);
    return module.exports;
  }
  return load;
}
function tokenEnv(){return {TOKEN_DO:{idFromName:name=>name,get:()=>({fetch:async()=>Response.json({token:'fake-review-token'})})}};}
function tokenState(){
  const storage=new Map([['baidu-token',{accessToken:'fake-access',refreshToken:'fake-refresh',expiresAt:Date.now()+86400000,scope:'basic netdisk'}]]);
  return {storage,state:{storage:{get:async key=>storage.get(key),put:async(key,value)=>{storage.set(key,value);},delete:async key=>storage.delete(key)}}};
}
const fakeCredentials={BAIDU_DISK_APP_KEY:'fake-key',BAIDU_DISK_SECRET_KEY:'fake-secret'};
async function probe(id,kind,title,run){
  try{results.push({id,kind,title,status:'confirmed',details:await run()});}
  catch(error){results.push({id,kind,title,status:'failed',error:error.stack});}
}
await probe('C1','control','206 and Range survive an allowed redirect',async()=>{
  const calls=[];
  const load=loader(async(url,init)=>{
    calls.push({range:init.headers.Range,ua:init.headers['User-Agent'],redirect:init.redirect});
    return calls.length===1?new Response(null,{status:302,headers:{Location:'https://download.baidupcs.com/audio.mp3'}}):
      new Response(new Uint8Array([1,2,3]),{status:206,headers:{'Content-Range':'bytes 10-12/100','Content-Length':'3','Content-Type':'audio/mpeg'}});
  });
  const {BaiduPanClient}=load('baidu/client.ts');
  const stream=await new BaiduPanClient(tokenEnv()).openDlink('https://pan.baidu.com/dlink','bytes=10-12');
  assert.equal(stream.status,206);assert.equal(stream.contentRange,'bytes 10-12/100');
  assert.equal((await new Response(stream.body).arrayBuffer()).byteLength,3);
  assert.ok(calls.every(c=>c.range==='bytes=10-12'&&c.ua==='pan.baidu.com'&&c.redirect==='manual'));
  return {fetchCalls:calls.length,status:206,contentRange:stream.contentRange};
});
await probe('R1','finding','403, 416, 429 and 500 become 404 NOT_FOUND',async()=>{
  const observations=[];
  for(const status of [403,416,429,500]){
    const load=loader(async()=>new Response('upstream failure',{status,headers:status===416?{'Content-Range':'bytes */100'}:{}}));
    const {BaiduPanClient}=load('baidu/client.ts');const {toErrorResponse}=load('support/http.ts');
    let error;try{await new BaiduPanClient(tokenEnv()).openDlink('https://pan.baidu.com/dlink','bytes=200-');}catch(caught){error=caught;}
    assert.ok(error);const response=toErrorResponse(error);const body=await response.json();
    assert.equal(response.status,404);assert.equal(body.error,'NOT_FOUND');assert.equal(response.headers.get('Content-Range'),null);
    observations.push({upstreamStatus:status,apiStatus:response.status,apiError:body.error});
  }
  return observations;
});
await probe('R2','finding','Temporary OAuth server_error deletes valid stored credentials',async()=>{
  const load=loader(async()=>Response.json({error:'server_error',error_description:'temporary'},{status:503}));
  const {BaiduTokenObject}=load('baidu/token-object.ts');const {storage,state}=tokenState();
  const response=await new BaiduTokenObject(state,fakeCredentials).fetch(new Request('https://do/refresh',{method:'POST'}));
  assert.equal(response.status,400);assert.equal(storage.has('baidu-token'),false);
  return {oauthStatus:503,oauthError:'server_error',storedCredentialsDeleted:true};
});
await probe('R3','finding','Five concurrent forced refreshes cause five OAuth exchanges',async()=>{
  let calls=0;const load=loader(async()=>{const n=++calls;return Response.json({access_token:'fake-access-'+n,refresh_token:'fake-refresh-'+n,expires_in:86400});});
  const {BaiduTokenObject}=load('baidu/token-object.ts');const {state}=tokenState();const service=new BaiduTokenObject(state,fakeCredentials);
  const responses=await Promise.all(Array.from({length:5},()=>service.fetch(new Request('https://do/refresh',{method:'POST'}))));
  assert.ok(responses.every(r=>r.status===200));assert.equal(calls,5);
  return {concurrentRequests:5,oauthRefreshCalls:calls};
});
await probe('R4','finding','Offset sync skips an existing song after an earlier deletion',async()=>{
  const {sync}=loader()('services/sync-service.ts');
  let files=Array.from({length:61},(_,i)=>({fs_id:i+1,path:'/music/'+String(i+1).padStart(3,'0')+'.mp3',server_filename:(i+1)+'.mp3',isdir:0,size:100,category:2}));
  const indexed=new Map();let scans=0;let mkdirCalls=0;
  const remote={mkdir:async()=>{mkdirCalls++;},listRecursive:async()=>{scans++;return {entries:files,truncated:false};},fileMetas:async()=>[]};
  const repo={findPathsUnder:async()=>[...indexed.keys()],upsertAssets:async rows=>{for(const row of rows)indexed.set(row.path,row);},setMissingByPaths:async()=>{}};
  const first=await sync({BAIDU_BASE_DIR:'/music'},repo,remote,null,0);assert.equal(first.nextOffset,30);
  files=files.slice(1);const last=await sync({BAIDU_BASE_DIR:'/music'},repo,remote,null,first.nextOffset);assert.equal(last.nextOffset,null);
  const missed=files.filter(f=>!indexed.has(f.path)).map(f=>f.path);
  assert.equal(missed.length,1);assert.equal(missed[0],'/music/031.mp3');
  return {initialFiles:61,remainingFiles:60,fullScans:scans,mkdirCalls,missed,reportedComplete:true};
});
await probe('R5','finding','A session issued before password change remains valid',async()=>{
  const load=loader();const {handleApi}=load('routes/api.ts');const {signJwt}=load('auth/jwt.ts');const {hashPassword}=load('auth/password.ts');
  const user={id:1,username:'reviewer',password_hash:await hashPassword('Old-review-password')};const secret='fake-review-secret';let updates=0;
  const db={prepare(sql){let args=[];return {
    bind(...values){args=values;return this;},
    async first(){if(sql.includes('system_config'))return {config_val:secret};if(sql.includes('FROM app_user WHERE'))return {...user};throw Error('Unexpected SQL: '+sql);},
    async run(){if(sql.startsWith('UPDATE app_user SET password_hash')){user.password_hash=args[0];updates++;return {meta:{changes:1}};}throw Error('Unexpected SQL mutation: '+sql);}
  };}};
  const env={...tokenEnv(),DB:db};const oldSession=await signJwt(user.username,secret,3600);const cookie='picman_token='+encodeURIComponent(oldSession);
  const changed=await handleApi(new Request('https://app.test/api/auth/password',{method:'POST',headers:{Cookie:cookie,'Content-Type':'application/json'},body:JSON.stringify({oldPassword:'Old-review-password',newPassword:'New-review-password'})}),env);
  assert.equal(changed.status,204);assert.equal(updates,1);
  const stillValid=await handleApi(new Request('https://app.test/api/auth/me',{headers:{Cookie:cookie}}),env);assert.equal(stillValid.status,200);
  return {passwordUpdateStatus:204,oldSessionStatusAfterChange:200};
});
await probe('R6','finding','A permission/path error causes existing subtree files to be marked missing',async()=>{
  const load=loader(async url=>new URL(url).searchParams.get('dir')==='/music'?
    Response.json({errno:0,list:[{path:'/music/private',isdir:1}]}):Response.json({errno:-7,errmsg:'path invalid or permission denied'}));
  const {BaiduPanClient}=load('baidu/client.ts');const {sync}=load('services/sync-service.ts');const client=new BaiduPanClient(tokenEnv());client.mkdir=async()=>{};
  const missing=[];const repo={findPathsUnder:async()=>['/music/private/existing.mp3'],upsertAssets:async()=>{},setMissingByPaths:async paths=>{missing.push(...paths);}};
  const result=await sync({BAIDU_BASE_DIR:'/music'},repo,client);assert.equal(result.nextOffset,null);assert.equal(result.removed,1);assert.equal(missing[0],'/music/private/existing.mp3');
  return {upstreamErrno:-7,markedMissing:missing,reportedComplete:true};
});
await probe('C2','control','A redirect outside the domain allowlist is rejected',async()=>{
  let calls=0;const load=loader(async()=>{calls++;return new Response(null,{status:302,headers:{Location:'http://127.0.0.1/private'}});});
  const {BaiduPanClient}=load('baidu/client.ts');
  await assert.rejects(()=>new BaiduPanClient(tokenEnv()).openDlink('https://pan.baidu.com/dlink'),/白名单/);assert.equal(calls,1);
  return {fetchCalls:calls,untrustedRedirectFetched:false};
});
const failures=results.filter(r=>r.status==='failed');
console.log(JSON.stringify({reference,scope:'Actual source executed with mocked HTTP and storage; no live Baidu or Cloudflare calls',
  notice:'Confirmed findings are reproduced defects, not passed product requirements.',
  findingsConfirmed:results.filter(r=>r.kind==='finding'&&r.status==='confirmed').length,
  controlsConfirmed:results.filter(r=>r.kind==='control'&&r.status==='confirmed').length,failedProbes:failures.length,results},null,2));
process.exitCode=failures.length?1:0;
