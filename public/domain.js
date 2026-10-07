export const stages=['New Order','Fabric','Cutting','Stitching','Embroidery / Handwork','Fitting','Alteration','Ready','Delivered','Cancelled'];
export const expenseCategories=['Salary','Karigar','Fabric','Dye','Packaging','Studio','Marketing/PR','Courier','Miscellaneous'];
export const purchaseCategories=['Fabric','Lining','Buttons','Zips','Hooks','Interfacing','Packaging','Labels','Tags','Embroidery materials','Other'];
export const modes=['UPI','Cash','Bank transfer','Card','Other'];
export const n=x=>Number(x)||0;
export const round=v=>Math.round((v+Number.EPSILON)*100)/100;
export const sum=(rows,key='amount')=>round(rows.reduce((s,r)=>s+n(r[key]),0));
export const today=()=>new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Kolkata',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
export function addDays(day,count){const d=new Date(day+'T12:00:00Z');d.setUTCDate(d.getUTCDate()+count);return d.toISOString().slice(0,10);}
export function weekRange(day){const d=new Date(day+'T12:00:00Z');const start=addDays(day,-((d.getUTCDay()+6)%7));return [start,addDays(start,6)];}
export function inRange(day,start,end){return !!day&&day>=start&&day<=end;}
export function monthRange(month){const [y,m]=month.split('-').map(Number);return [month+'-01',new Date(Date.UTC(y,m,0)).toISOString().slice(0,10)];}
export const activeOrder=o=>!['Delivered','Cancelled'].includes(o.status);
export const sortOrders=rows=>[...rows].sort((a,b)=>(a.next_delivery||a.due_date||'9999').localeCompare(b.next_delivery||b.due_date||'9999')||a.reference.localeCompare(b.reference));
export const paymentsFor=(data,id)=>data.order_payments.filter(p=>p.order_id===id&&!p.voided);
export const received=(data,id)=>sum(paymentsFor(data,id));
export const balance=(data,o)=>Math.max(0,round(n(o.amount)-received(data,o.id)));
export function paymentStatus(data,o){return balance(data,o)===0?'Paid':received(data,o.id)>0?'Part paid':'Unpaid';}
export const salaryPayments=(data,id)=>data.salary_payments.filter(p=>p.salary_id===id&&!p.voided);
export const salaryBalance=(data,s)=>Math.max(0,round(n(s.salary)-n(s.deduction)-sum(salaryPayments(data,s.id))));
export function monthSummary(data,month){
 const [start,end]=monthRange(month),orders=data.orders.filter(o=>o.status!=='Cancelled'&&inRange(o.order_date,start,end));
 const purchases=data.purchases.filter(p=>inRange(p.purchase_date,start,end)),expenses=data.expenses.filter(e=>inRange(e.expense_date,start,end));
 const alterations=data.alterations.filter(a=>a.status!=='Cancelled'&&inRange(a.received_date,start,end));
 const salaries=data.salaries.filter(s=>inRange(s.period_start,start,end));
 const sales=sum(orders),allocatedCollected=orders.reduce((v,o)=>v+received(data,o.id),0),cashCollected=sum(data.order_payments.filter(p=>!p.voided&&inRange(p.payment_date,start,end)));
 const costs={materials:sum(purchases)+sum(expenses.filter(e=>e.category==='Fabric')),production:sum(expenses.filter(e=>['Tailoring','Embroidery','Dyer'].includes(e.category)))+sum(alterations,'additional_cost'),salaries:salaries.reduce((v,s)=>v+n(s.salary)-n(s.deduction),0),rent:sum(expenses.filter(e=>e.category==='Rent')),marketing:sum(expenses.filter(e=>e.category==='Marketing/PR')),packaging:sum(expenses.filter(e=>['Packaging','Courier'].includes(e.category))),other:sum(expenses.filter(e=>!['Fabric','Tailoring','Embroidery','Dyer','Rent','Marketing/PR','Packaging','Courier'].includes(e.category)))};
 const totalCost=Math.round(Object.values(costs).reduce((a,b)=>a+b,0)*100)/100,profit=Math.round((sales-totalCost)*100)/100;
 return {orders:orders.length,sales,allocatedCollected,cashCollected,outstanding:Math.max(0,sales-allocatedCollected),costs,totalCost,profit,margin:sales?profit/sales*100:null};
}
export function orderCost(data,o){
 const purchases=data.purchases.filter(p=>p.order_id===o.id),expenses=data.expenses.filter(e=>e.order_id===o.id),alterations=data.alterations.filter(a=>a.order_id===o.id&&a.status!=='Cancelled');
 const groups={fabric:sum(purchases.filter(p=>['Fabric','Lining'].includes(p.category)))+sum(expenses.filter(e=>e.category==='Fabric')),tailoring:sum(expenses.filter(e=>e.category==='Tailoring')),embroidery:sum(purchases.filter(p=>p.category==='Embroidery material'))+sum(expenses.filter(e=>e.category==='Embroidery')),packaging:sum(purchases.filter(p=>p.category==='Packaging'))+sum(expenses.filter(e=>['Packaging','Courier'].includes(e.category))),other:sum(purchases.filter(p=>!['Fabric','Lining','Embroidery material','Packaging'].includes(p.category)))+sum(expenses.filter(e=>!['Fabric','Tailoring','Embroidery','Packaging','Courier'].includes(e.category)))+sum(alterations,'additional_cost')};
 const total=round(Object.values(groups).reduce((a,b)=>a+b,0));return {groups,total,profit:round(n(o.amount)-total)};
}

export const productTotal=items=>round(items.reduce((total,item)=>total+n(item.quantity)*n(item.price),0));
export const overallStage=items=>items.filter(i=>i.status!=='Cancelled').map(i=>i.status).sort((a,b)=>stages.indexOf(a)-stages.indexOf(b))[0]||'Cancelled';
export const rolePermissions={production:['orders','studio','production','tasks','calendar'],team:['tasks'],accounts:['payments','expenses','purchases']};

// Natural invoice order, with unnumbered records last and deterministic ties.
export const sortOrdersByInvoice=rows=>[...rows].sort((a,b)=>{const x=String(a.invoice_number||''),y=String(b.invoice_number||'');return (x&&y?x.localeCompare(y,'en',{numeric:true}):x?-1:y?1:0)||String(a.reference||'').localeCompare(String(b.reference||''),'en',{numeric:true})||String(a.id||'').localeCompare(String(b.id||''));});
