begin;
alter table public.lm_orders add column payment_mode text check(payment_mode in ('UPI','Cash'));
alter table public.lm_order_payments alter column payment_mode drop not null;
alter table public.lm_order_payments alter column payment_mode drop default;
update public.lm_orders o set payment_mode=(select p.payment_mode from public.lm_order_payments p where p.order_id=o.id and p.kind='Advance' and not p.voided and p.payment_mode in ('UPI','Cash') order by p.created_at,p.id limit 1);
CREATE OR REPLACE FUNCTION lm_private.save_order(p_order jsonb, p_items jsonb, p_id uuid DEFAULT NULL::uuid, p_advance numeric DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare oid uuid;cid uuid;client_name text;item jsonb;iid uuid;ids uuid[]:='{}';total numeric;stage text;stages text[]:=array['New Order','Fabric','Cutting','Stitching','Embroidery / Handwork','Fitting','Alteration','Ready','Delivered'];isfinance boolean;olditem public.lm_order_items;chosen_mode text;begin
 if not lm_private.can('orders') then raise insufficient_privilege using message='Orders access required';end if;
 isfinance=lm_private.can('payments');
 if not isfinance and p_id is null then raise insufficient_privilege using message='Only staff with orders and payments access can create orders';end if;
 if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)<1 or jsonb_array_length(p_items)>100 then raise exception 'Add between 1 and 100 products';end if;
 if p_id is not null then perform 1 from public.lm_orders where id=p_id for update;if not found then raise exception 'Order unavailable';end if;oid=p_id;end if;
 if isfinance then
  chosen_mode=nullif(p_order->>'payment_mode','');if chosen_mode='Other' then chosen_mode=null;end if;
  if chosen_mode is not null and chosen_mode not in ('UPI','Cash') then raise exception 'Choose UPI, Cash or leave Payment Mode blank';end if;
  cid=(p_order->>'customer_id')::uuid;select name into client_name from public.lm_customers where id=cid;if client_name is null then raise exception 'Choose a client';end if;
  if p_id is null then oid=coalesce((p_order->>'id')::uuid,gen_random_uuid());insert into public.lm_orders(id,reference,customer_id,customer_name,order_date,due_date,fitting_date,payment_due_date,product,quantity,amount,status,assigned_to,notes) values(oid,p_order->>'reference',cid,client_name,(p_order->>'order_date')::date,(p_order->>'due_date')::date,nullif(p_order->>'fitting_date','')::date,(p_order->>'payment_due_date')::date,'Products',1,0,'New Order',p_order->>'assigned_to',p_order->>'notes');end if;
  if (p_order->>'due_date')::date<(p_order->>'order_date')::date then raise exception 'Delivery date cannot precede order date';end if;
 else
  if p_order ?| array['amount','customer_id','reference','order_date','payment_due_date','advance','id','overall_state','payment_mode','invoice_date'] then raise insufficient_privilege using message='Financial and client changes require owner or accounts access';end if;
 end if;
 for item in select value from jsonb_array_elements(p_items) loop
  iid=coalesce((item->>'id')::uuid,gen_random_uuid());ids=array_append(ids,iid);
  if exists(select 1 from public.lm_order_items where id=iid and order_id<>oid) then raise insufficient_privilege using message='Product belongs to another order';end if;
  if isfinance then
   insert into public.lm_order_items(id,order_id,position,name,description,quantity,price,fabric,due_date,status,notes) values(iid,oid,coalesce((item->>'position')::integer,0),item->>'name',item->>'description',(item->>'quantity')::numeric,(item->>'price')::numeric,item->>'fabric',(item->>'due_date')::date,item->>'status',item->>'notes') on conflict(id) do update set position=excluded.position,name=excluded.name,description=excluded.description,quantity=excluded.quantity,price=excluded.price,fabric=excluded.fabric,due_date=excluded.due_date,status=excluded.status,notes=excluded.notes;
  else
   if item?'price' then raise insufficient_privilege using message='Product prices are private';end if;
   select * into olditem from public.lm_order_items where id=iid and order_id=oid;if not found then raise insufficient_privilege using message='Only the owner can add or remove products';end if;
   update public.lm_order_items set name=item->>'name',description=item->>'description',fabric=item->>'fabric',due_date=(item->>'due_date')::date,status=item->>'status',notes=item->>'notes' where id=iid;
  end if;
 end loop;
 if not isfinance and (select count(*) from public.lm_order_items where order_id=oid)<>cardinality(ids) then raise insufficient_privilege using message='Only the owner can remove products';end if;
 if isfinance then delete from public.lm_order_items where order_id=oid and not id=any(ids);end if;
 select round(sum(quantity*price),2) into total from public.lm_order_items where order_id=oid;
 select coalesce((select status from public.lm_order_items where order_id=oid and status<>'Cancelled' order by array_position(stages,status) limit 1),'Cancelled') into stage;
 if (isfinance and p_order->>'overall_state'='Cancelled') or (not isfinance and exists(select 1 from public.lm_orders where id=oid and status='Cancelled')) then stage='Cancelled';end if;
 if cardinality(ids)<>(select count(distinct x) from unnest(ids) x) then raise exception 'Each product must be included once';end if;
 if isfinance then update public.lm_orders set reference=p_order->>'reference',customer_id=cid,customer_name=client_name,order_date=(p_order->>'order_date')::date,due_date=(p_order->>'due_date')::date,fitting_date=nullif(p_order->>'fitting_date','')::date,payment_due_date=(p_order->>'payment_due_date')::date,payment_mode=case when p_order?'payment_mode' then chosen_mode else payment_mode end,invoice_date=coalesce(nullif(p_order->>'invoice_date','')::date,(p_order->>'order_date')::date),amount=total,product=(select string_agg(name,' · ' order by position) from public.lm_order_items where order_id=oid),quantity=(select sum(quantity) from public.lm_order_items where order_id=oid),status=stage,assigned_to=p_order->>'assigned_to',notes=p_order->>'notes' where id=oid;
 else update public.lm_orders set fitting_date=nullif(p_order->>'fitting_date','')::date,due_date=(p_order->>'due_date')::date,status=stage,assigned_to=p_order->>'assigned_to',notes=p_order->>'notes' where id=oid;end if;
 if isfinance and p_id is not null and p_order?'payment_mode' then
  update public.lm_order_payments set payment_mode=chosen_mode where id=(select id from public.lm_order_payments where order_id=oid and kind='Advance' and not voided order by created_at,id limit 1);
 end if;
 if p_advance<0 then raise exception 'Advance cannot be negative';end if;
 if p_advance>0 then
  if not isfinance or p_id is not null then raise insufficient_privilege using message='Use Record payment for existing orders';end if;
  insert into public.lm_order_payments(order_id,payment_date,amount,kind,payment_mode) values(oid,(p_order->>'advance_date')::date,p_advance,'Advance',chosen_mode);
 end if;
 return jsonb_build_object('id',oid,'saved',true);
end $function$
;
CREATE OR REPLACE FUNCTION lm_private.invoice(p_order_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare o public.lm_orders;begin
 if auth.uid() is null or not lm_private.is_staff() or not lm_private.can('payments') or not lm_private.can('clients') then raise insufficient_privilege using message='Client and payment access required to generate invoices';end if;
 select * into o from public.lm_orders where id=p_order_id;
 if not found then raise exception 'Order is unavailable';end if;
 if o.status='Cancelled' then raise exception 'Cancelled orders cannot be invoiced';end if;
 return jsonb_build_object('order',to_jsonb(o)-'delivery_previous_stages','client',(select jsonb_build_object('name',c.name,'phone',c.phone,'address',c.address) from public.lm_customers c where c.id=o.customer_id),'items',(select coalesce(jsonb_agg(jsonb_build_object('id',i.id,'name',i.name,'fabric',i.fabric,'quantity',i.quantity,'price',i.price) order by i.position),'[]') from public.lm_order_items i where i.order_id=o.id),'payments',(select coalesce(jsonb_agg(jsonb_build_object('amount',p.amount,'payment_date',p.payment_date,'kind',p.kind,'payment_mode',p.payment_mode)),'[]') from public.lm_order_payments p where p.order_id=o.id and not p.voided));
end $function$
;
CREATE OR REPLACE FUNCTION lm_private.workspace()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare result jsonb:='{}';s public.lm_staff; rows jsonb; financial boolean;day date:=(now() at time zone 'Asia/Kolkata')::date;month_start date;month_end date; sales numeric;collected numeric;outstanding numeric;costs numeric;begin
 select * into s from public.lm_staff where user_id=auth.uid();
 if not found then raise insufficient_privilege using message='Your account has not been approved for studio access';end if;
 financial=lm_private.can('payments');
 result=jsonb_build_object('profile',jsonb_build_object('user_id',s.user_id,'role',s.role,'name',s.display_name,'permissions',s.permissions),'people',(select coalesce(jsonb_agg(jsonb_build_object('user_id',user_id,'name',coalesce(display_name,'Team member'))),'[]') from public.lm_staff));
 if lm_private.can('orders') or lm_private.can('clients') or financial or lm_private.can('calendar') or lm_private.can('production') or lm_private.can('home') then
  select coalesce(jsonb_agg((case when financial then to_jsonb(o) else to_jsonb(o)-array['amount','paid','payment_due_date','payment_mode'] end)||jsonb_build_object('next_delivery',coalesce((select min(coalesce(i.due_date,o.due_date)) from public.lm_order_items i where i.order_id=o.id and i.status not in ('Delivered','Cancelled')),o.due_date))),'[]') into rows from public.lm_orders o;
  result=result||jsonb_build_object('orders',rows);
  select coalesce(jsonb_agg(case when financial then to_jsonb(i) else to_jsonb(i)-'price' end order by i.position),'[]') into rows from public.lm_order_items i;
  result=result||jsonb_build_object('order_items',rows);
 end if;
 if lm_private.can('clients') then result=result||jsonb_build_object('customers',(select coalesce(jsonb_agg(to_jsonb(c)),'[]') from public.lm_customers c));end if;
 if lm_private.can('studio') or lm_private.can('production') or lm_private.can('purchases') or lm_private.can('calendar') or lm_private.can('home') then result=result||jsonb_build_object('studio_pieces',(select coalesce(jsonb_agg(to_jsonb(p)),'[]') from public.lm_studio_pieces p));end if;
 if lm_private.can('production') or lm_private.can('calendar') or lm_private.can('home') then result=result||jsonb_build_object('jobs',(select coalesce(jsonb_agg(case when lm_private.can('expenses') then to_jsonb(j) else to_jsonb(j)-'payment_status' end),'[]') from public.lm_jobs j));end if;
 if lm_private.can('tasks') or lm_private.can('home') or lm_private.can('calendar') then
  result=result||jsonb_build_object('tasks',(select coalesce(jsonb_agg(to_jsonb(t)),'[]') from public.lm_tasks t where s.role='owner' or t.assigned_user_id=s.user_id or t.created_by=s.user_id));
 end if;
 if lm_private.can('calendar') or lm_private.can('home') then result=result||jsonb_build_object('events',(select coalesce(jsonb_agg(to_jsonb(e)),'[]') from public.lm_events e where s.role='owner' or e.assigned_user_id=s.user_id or e.created_by=s.user_id));end if;
 if financial then result=result||jsonb_build_object('order_payments',(select coalesce(jsonb_agg(to_jsonb(p)),'[]') from public.lm_order_payments p));end if;
 if lm_private.can('expenses') then result=result||jsonb_build_object('expenses',(select coalesce(jsonb_agg(to_jsonb(e)),'[]') from public.lm_expenses e));end if;
 if lm_private.can('purchases') then result=result||jsonb_build_object('purchases',(select coalesce(jsonb_agg(to_jsonb(p)),'[]') from public.lm_purchases p));end if;
 if lm_private.can('salaries') then result=result||jsonb_build_object('salaries',(select coalesce(jsonb_agg(to_jsonb(payroll)),'[]') from public.lm_salaries payroll),'salary_payments',(select coalesce(jsonb_agg(to_jsonb(p)),'[]') from public.lm_salary_payments p));end if;
 if lm_private.can('orders') then result=result||jsonb_build_object('alterations',(select coalesce(jsonb_agg(case when lm_private.can('expenses') then to_jsonb(a) else to_jsonb(a)-'additional_cost' end),'[]') from public.lm_alterations a));end if;
 if s.role='owner' then result=result||jsonb_build_object('inventory',(select coalesce(jsonb_agg(to_jsonb(i)),'[]') from public.lm_inventory i),'members',(select coalesce(jsonb_agg(jsonb_build_object('user_id',st.user_id,'role',st.role,'permissions',st.permissions,'name',st.display_name,'email',u.email)),'[]') from public.lm_staff st join auth.users u on u.id=st.user_id));end if;
 if lm_private.can('home') then
  month_start=date_trunc('month',day)::date;month_end=(month_start+interval '1 month')::date;
  select coalesce(sum(amount),0) into sales from public.lm_orders where status<>'Cancelled' and order_date>=month_start and order_date<month_end;
  select coalesce(sum(amount),0) into collected from public.lm_order_payments where not voided and payment_date>=month_start and payment_date<month_end;
  select coalesce(sum(greatest(0,o.amount-coalesce((select sum(p.amount) from public.lm_order_payments p where p.order_id=o.id and not p.voided),0))),0) into outstanding from public.lm_orders o where o.status<>'Cancelled';
  costs=coalesce((select sum(amount) from public.lm_expenses where expense_date>=month_start and expense_date<month_end),0)+coalesce((select sum(amount) from public.lm_purchases where purchase_date>=month_start and purchase_date<month_end),0)+coalesce((select sum(salary-deduction) from public.lm_salaries where period_start>=month_start and period_start<month_end),0)+coalesce((select sum(additional_cost) from public.lm_alterations where status<>'Cancelled' and received_date>=month_start and received_date<month_end),0);
  result=result||jsonb_build_object('home',jsonb_build_object('sales',sales,'collected',collected,'outstanding',outstanding,'costs',costs));
 end if;
 if lm_private.can('salaries') then result=result||jsonb_build_object('salary_profiles',(select coalesce(jsonb_agg(to_jsonb(p)),'[]') from public.lm_salary_profiles p),'salary_payouts',(select coalesce(jsonb_agg(to_jsonb(p)),'[]') from public.lm_salary_payouts p));end if;
 if lm_private.can('purchases') then result=result||jsonb_build_object('purchase_payments',(select coalesce(jsonb_agg(to_jsonb(p)),'[]') from public.lm_purchase_payments p));end if;
 return result;
end $function$
;
commit;
