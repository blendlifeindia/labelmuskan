const {url,key}=window.LM_CONFIG;
let session=null,refreshPromise=null;
try{session=JSON.parse(sessionStorage.getItem('lm-session'));}catch{}
export const getSession=()=>session;
function setSession(value){session=value;value?sessionStorage.setItem('lm-session',JSON.stringify(value)):sessionStorage.removeItem('lm-session');}
async function fetchJson(path,options={},auth=true){
 const response=await fetch(url+path,{...options,headers:{apikey:key,'Content-Type':'application/json',...(auth&&session?{Authorization:'Bearer '+session.access_token}:{}),...options.headers}});
 const text=await response.text();let body;try{body=text?JSON.parse(text):null;}catch{body=null;}
 if(!response.ok)throw Error(body?.message||body?.msg||body?.error_description||'Could not save changes. Please try again.');return body;
}
export async function request(path,options={},auth=true){
 if(auth&&session&&session.expires_at*1000<Date.now()+60000){
  refreshPromise??=fetchJson('/auth/v1/token?grant_type=refresh_token',{method:'POST',body:JSON.stringify({refresh_token:session.refresh_token})},false).then(setSession).catch(()=>{setSession(null);throw Error('Your session expired. Please sign in again.');}).finally(()=>refreshPromise=null);
  await refreshPromise;
 }
 return fetchJson(path,options,auth);
}
export async function signIn(email,password){setSession(await request('/auth/v1/token?grant_type=password',{method:'POST',body:JSON.stringify({email,password})},false));}
export async function signOut(){try{await request('/auth/v1/logout',{method:'POST'});}catch{}setSession(null);}
export const rpc=(name,body={})=>request('/rest/v1/rpc/lm_'+name,{method:'POST',body:JSON.stringify(body)});
export const workspace=()=>rpc('workspace');
export const save=async(table,body,id)=>[await rpc('save_record',{p_table:table,p_body:body,p_id:id||null})];
