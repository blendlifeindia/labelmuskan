import {today,addDays,monthRange,inRange,sum} from './domain.js';
export function overviewRange(preset,from='',to='',day=today()){
 if(preset==='all')return ['2026-03-01',day];
 if(preset==='today')return [day,day];
 if(preset==='yesterday'){const d=addDays(day,-1);return [d,d];}
 if(preset==='last'){const d=new Date(day+'T12:00:00Z');d.setUTCDate(1);d.setUTCMonth(d.getUTCMonth()-1);return monthRange(d.toISOString().slice(0,7));}
 if(preset==='custom'){if(!/^\d{4}-\d{2}-\d{2}$/.test(from)||!/^\d{4}-\d{2}-\d{2}$/.test(to)||from>to)throw Error('Choose a valid start and end date.');return [from,to];}
 return monthRange(day.slice(0,7));
}
export function rangeSummary(data,start,end){return {sales:sum(data.orders.filter(o=>o.status!=='Cancelled'&&inRange(o.order_date,start,end))),collected:sum(data.order_payments.filter(p=>!p.voided&&inRange(p.payment_date,start,end))),outstanding:sum(data.orders.filter(o=>o.status!=='Cancelled'&&o.order_date<=end).map(o=>({amount:Math.max(0,Number(o.amount)-sum(data.order_payments.filter(p=>p.order_id===o.id&&!p.voided&&p.payment_date<=end)))})))};}
export function paymentMatches(data,o,filter,day=today()){
 const paid=sum(data.order_payments.filter(p=>p.order_id===o.id&&!p.voided)),remaining=Math.max(0,Number(o.amount)-paid);
 return filter==='all'||filter==='paid'&&remaining===0||filter==='unpaid'&&remaining>0||filter==='partial'&&remaining>0&&paid>0||filter==='overdue'&&remaining>0&&!!o.payment_due_date&&o.payment_due_date<day;
}
export function whatsappURL(phone){let digits=String(phone||'').replace(/\D/g,'');if(digits.length===10)digits='91'+digits;if(digits.startsWith('00'))digits=digits.slice(2);return digits.length>=8&&digits.length<=15?'https://wa.me/'+digits:null;}
