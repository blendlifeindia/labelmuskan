// Local-only UI test server. Uses synthetic records and never connects to Supabase.
import http from 'node:http';
import {readFile} from 'node:fs/promises';
import {resolve,extname} from 'node:path';
import {randomUUID} from 'node:crypto';
import {today,addDays} from '../public/domain.js';
const day=today(),client=randomUUID(),oid=randomUUID(),root=resolve('public');
const data={staff:[{user_id:'qa-user'}],customers:[{id:client,name:'Preview Client',phone:'9000000000',city:'Jaipur',measurements:'Bust 34 · Waist 28',preferences:'Soft pastels'}],orders:[{id:oid,reference:'LM-124',customer_id:client,customer_name:'Preview Client',order_date:day,due_date:addDays(day,2),payment_due_date:day,product:'Ivory embroidered set',quantity:1,amount:48000,status:'Stitching',assigned_to:'Studio team'},{id:randomUUID(),reference:'LM-123',customer_id:client,order_date:day,due_date:addDays(day,-1),amount:12000,status:'Cutting',product:'Kurta set'}],order_payments:[{id:randomUUID(),order_id:oid,payment_date:day,kind:'Advance',amount:12000,payment_mode:'UPI',voided:false}],purchases:[{id:randomUUID(),purchase_date:day,vendor:'Preview Fabrics',item:'Ivory fabric',category:'Fabric',quantity:4,amount:12000,order_id:oid,status:'Paid'}],expenses:[{id:randomUUID(),expense_date:day,description:'Tailoring',category:'Tailoring',amount:3000,paid_by:'Owner',payment_mode:'UPI',order_id:oid}],salaries:[],salary_payments:[],alterations:[],inventory:[]};
const send=(res,status,body)=>{res.writeHead(status,{'Content-Type':'application/json'});res.end(JSON.stringify(body));};
http.createServer(async(req,res)=>{
 try{
  const u=new URL(req.url,'http://127.0.0.1:3001'),path=u.pathname;
  if(path==='/config.js'){res.writeHead(200,{'Content-Type':'text/javascript'});res.end('window.LM_CONFIG={url:"http://127.0.0.1:3001",key:"local-test"};');return;}
  if(path.startsWith('/auth/')){send(res,200,{access_token:'local-only',refresh_token:'local-only',expires_at:Math.floor(Date.now()/1000)+3600,user:{id:'qa-user',email:'preview@local.test'}});return;}
  if(path.startsWith('/rest/')){
   let body={};if(req.method!=='GET'){let raw='';for await(const c of req)raw+=c;body=raw?JSON.parse(raw):{};}
   if(path==='/rest/v1/rpc/lm_create_order'){
    let cid=body.p_order.customer_id;if(body.p_new_client){cid=randomUUID();data.customers.push({id:cid,...body.p_new_client});}
    const row={id:randomUUID(),created_at:new Date().toISOString(),...body.p_order,customer_id:cid};data.orders.push(row);if(body.p_advance)data.order_payments.push({id:randomUUID(),order_id:row.id,amount:body.p_advance,payment_date:row.advance_date,kind:'Advance',payment_mode:row.payment_mode});send(res,200,row);return;
   }
   const name=path.split('/').pop().replace(/^lm_/,''),rows=data[name];if(!rows){send(res,404,{message:'Unknown test table'});return;}
   if(req.method==='GET'){const offset=Number(u.searchParams.get('offset')||0),limit=Number(u.searchParams.get('limit')||500);send(res,200,rows.slice(offset,offset+limit));return;}
   if(req.method==='PATCH'){const id=u.searchParams.get('id')?.slice(3),row=rows.find(r=>r.id===id);Object.assign(row,body);send(res,200,[row]);return;}
   const row={id:randomUUID(),created_at:new Date().toISOString(),...body};rows.push(row);send(res,201,[row]);return;
  }
  const file=resolve(root,'.'+(path==='/'?'/index.html':decodeURIComponent(path)));if(!file.startsWith(root+'/')){res.writeHead(403);res.end();return;}
  const content=await readFile(file);res.writeHead(200,{'Content-Type':{'.html':'text/html','.js':'text/javascript','.css':'text/css','.svg':'image/svg+xml'}[extname(file)]||'text/plain','Cache-Control':'no-store'});res.end(content);
 }catch(err){send(res,500,{message:err.message});}
}).listen(3001,'127.0.0.1',()=>console.log('Synthetic UI test preview: http://127.0.0.1:3001'));
