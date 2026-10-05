begin;
alter table public.lm_staff add column role text not null default 'team' check(role in ('owner','production','team','accounts')), add column permissions text[] not null default array['tasks'], add column display_name text;
update public.lm_staff s set role='owner',permissions='{}',display_name='Muskan' from auth.users u where s.user_id=u.id and lower(u.email)='muskanagarwal2727@gmail.com' and u.email_confirmed_at is not null;
do $$ begin if (select count(*) from public.lm_staff where role='owner')<>1 then raise exception 'Verified owner account is required'; end if; end $$;
create unique index lm_one_owner on public.lm_staff(role) where role='owner';
create function lm_private.can(p_permission text) returns boolean language sql stable security definer set search_path='' as $$ select exists(select 1 from public.lm_staff where user_id=auth.uid() and (role='owner' or p_permission=any(permissions))); $$;
revoke all on function lm_private.can(text) from public,anon;
grant execute on function lm_private.can(text) to authenticated;
alter table public.lm_customers add column measurement_date date,add column alteration_notes text;
alter table public.lm_orders add column fitting_date date;
alter table public.lm_orders drop constraint lm_orders_status_check;
update public.lm_orders set status=case status when 'Measurement Pending' then 'New Order' when 'Fabric Pending' then 'Fabric' when 'Embroidery/Handwork' then 'Embroidery / Handwork' when 'Trial Pending' then 'Fitting' else status end;
alter table public.lm_orders add constraint lm_orders_status_check check(status in ('New Order','Fabric','Cutting','Stitching','Embroidery / Handwork','Fitting','Alteration','Ready','Delivered','Cancelled'));
create table public.lm_order_items(id uuid primary key default gen_random_uuid(),created_at timestamptz not null default now(),order_id uuid not null references public.lm_orders(id),position integer not null default 0,name text not null check(length(trim(name))>0),description text,quantity numeric not null check(quantity>0),price numeric not null check(price>=0),fabric text,due_date date,status text not null default 'New Order' check(status in ('New Order','Fabric','Cutting','Stitching','Embroidery / Handwork','Fitting','Alteration','Ready','Delivered','Cancelled')),notes text);
insert into public.lm_order_items(order_id,name,quantity,price,due_date,status,notes) select id,product,quantity,amount/quantity,due_date,status,notes from public.lm_orders;
create table public.lm_studio_pieces(id uuid primary key default gen_random_uuid(),created_at timestamptz not null default now(),name text not null check(length(trim(name))>0),collection text,kind text not null default 'Samples',description text,fabric text,quantity numeric not null default 1 check(quantity>0),due_date date,shoot_date date,status text not null default 'New Order' check(status in ('New Order','Fabric','Cutting','Stitching','Embroidery / Handwork','Fitting','Alteration','Ready','Delivered','Cancelled')),assigned_to text,notes text);
create table public.lm_jobs(id uuid primary key default gen_random_uuid(),created_at timestamptz not null default now(),karigar text not null check(length(trim(karigar))>0),work text not null,kind text not null check(kind in ('Tailor','Embroidery / Handwork','Dyer','Other')),order_item_id uuid references public.lm_order_items(id),studio_piece_id uuid references public.lm_studio_pieces(id),given_date date not null,due_date date,status text not null default 'In Progress' check(status in ('Pending','In Progress','Ready','Returned','Cancelled')),payment_status text not null default 'Unpaid' check(payment_status in ('Unpaid','Paid','Not due')),notes text,check(num_nonnulls(order_item_id,studio_piece_id)=1));
create table public.lm_tasks(id uuid primary key default gen_random_uuid(),created_at timestamptz not null default now(),created_by uuid not null default auth.uid() references auth.users(id),assigned_user_id uuid references public.lm_staff(user_id),title text not null check(length(trim(title))>0),category text not null default 'Studio',task_date date not null default current_date,task_time time,order_id uuid references public.lm_orders(id),studio_piece_id uuid references public.lm_studio_pieces(id),done boolean not null default false,notes text);
create table public.lm_events(id uuid primary key default gen_random_uuid(),created_at timestamptz not null default now(),created_by uuid not null default auth.uid() references auth.users(id),assigned_user_id uuid references public.lm_staff(user_id),title text not null check(length(trim(title))>0),category text not null default 'Shoot',event_date date not null,event_time time,order_id uuid references public.lm_orders(id),studio_piece_id uuid references public.lm_studio_pieces(id),notes text);
alter table public.lm_purchases add column studio_piece_id uuid references public.lm_studio_pieces(id),add column collection text;
alter table public.lm_purchases drop constraint lm_purchases_category_check;
alter table public.lm_purchases add constraint lm_purchases_category_check check(category in ('Fabric','Lining','Trims','Lace','Buttons','Zips','Hooks','Interfacing','Packaging','Labels','Tags','Embroidery material','Embroidery materials','Accessories','Other'));
alter table public.lm_expenses drop constraint lm_expenses_category_check;
update public.lm_expenses set category=case when category in ('Tailoring','Embroidery','Dyer') then 'Karigar' when category in ('Staff') then 'Salary' when category in ('Rent','Electricity','Repairs','Travel','Food/Hospitality') then 'Studio' when category='Miscellaneous' then 'Other' else category end;
alter table public.lm_expenses add constraint lm_expenses_category_check check(category in ('Salary','Karigar','Fabric','Packaging','Studio','Marketing/PR','Courier','Other'));
create index on public.lm_order_items(order_id);
create index on public.lm_jobs(order_item_id);
create index on public.lm_jobs(studio_piece_id);
create index on public.lm_purchases(studio_piece_id);
create index on public.lm_tasks(assigned_user_id,task_date);
create index on public.lm_tasks(created_by);
create index on public.lm_events(assigned_user_id,event_date);

-- Base tables are not exposed to browser roles. Checked, redacted RPCs below
-- provide operational access without revealing financial columns to production.
do $$ declare t text;p record;begin
 for t in select tablename from pg_tables where schemaname='public' and tablename like 'lm_%' loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from public,anon,authenticated',t);
  for p in select policyname from pg_policies where schemaname='public' and tablename=t loop execute format('drop policy %I on public.%I',p.policyname,t);end loop;
  execute format('create policy owner_only on public.%I for all to authenticated using ((select lm_private.can(''owner''))) with check ((select lm_private.can(''owner'')))',t);
 end loop;
end $$;
revoke execute on function public.lm_create_order(jsonb,numeric,jsonb) from authenticated,anon,public;

create function lm_private.workspace() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb:='{}';s public.lm_staff; rows jsonb; financial boolean;day date:=(now() at time zone 'Asia/Kolkata')::date;month_start date;month_end date; sales numeric;collected numeric;outstanding numeric;costs numeric;begin
 select * into s from public.lm_staff where user_id=auth.uid();
 if not found then raise insufficient_privilege using message='Your account has not been approved for studio access';end if;
 financial=lm_private.can('payments');
 result=jsonb_build_object('profile',jsonb_build_object('user_id',s.user_id,'role',s.role,'name',s.display_name,'permissions',s.permissions),'people',(select coalesce(jsonb_agg(jsonb_build_object('user_id',user_id,'name',coalesce(display_name,'Team member'))),'[]') from public.lm_staff));
 if lm_private.can('orders') or lm_private.can('clients') or financial or lm_private.can('calendar') or lm_private.can('production') or lm_private.can('home') then
  select coalesce(jsonb_agg((case when financial then to_jsonb(o) else to_jsonb(o)-array['amount','paid','payment_due_date'] end)||jsonb_build_object('next_delivery',coalesce((select min(coalesce(i.due_date,o.due_date)) from public.lm_order_items i where i.order_id=o.id and i.status not in ('Delivered','Cancelled')),o.due_date))),'[]') into rows from public.lm_orders o;
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
 if lm_private.can('salaries') then result=result||jsonb_build_object('salaries',(select coalesce(jsonb_agg(to_jsonb(s)),'[]') from public.lm_salaries s),'salary_payments',(select coalesce(jsonb_agg(to_jsonb(p)),'[]') from public.lm_salary_payments p));end if;
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
 return result;
end $$;

-- Record writes whitelist table, field, permission, and assignment together.
create function lm_private.save_record(p_table text,p_body jsonb,p_id uuid default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare allowed text[];permission text;keys text[];cols text;updates text;newid uuid; row_owner uuid;begin
 if auth.uid() is null or not lm_private.is_staff() then raise insufficient_privilege using message='Studio access required';end if;
 case p_table
 when 'customers' then permission='clients';allowed=array['name','phone','email','instagram','city','address','measurements','measurement_date','preferences','alteration_notes','notes'];
 when 'expenses' then permission='expenses';allowed=array['expense_date','description','category','amount','paid_by','payment_mode','order_id','notes'];
 when 'purchases' then permission='purchases';allowed=array['purchase_date','vendor','item','category','quantity','amount','order_id','studio_piece_id','collection','status','notes'];
 when 'salaries' then permission='salaries';allowed=array['staff_name','salary','frequency','period_start','period_end','deduction','notes'];
 when 'order_payments' then permission='payments';allowed=case when p_id is null then array['order_id','payment_date','amount','kind','payment_mode','notes'] else array['voided','notes'] end;
 when 'salary_payments' then permission='salaries';allowed=case when p_id is null then array['salary_id','payment_date','amount','kind','payment_mode','notes'] else array['voided','notes'] end;
 when 'studio_pieces' then permission='studio';allowed=array['name','collection','kind','description','fabric','quantity','due_date','shoot_date','status','assigned_to','notes'];
 when 'jobs' then permission='production';allowed=array['karigar','work','kind','order_item_id','studio_piece_id','given_date','due_date','status','notes'];if lm_private.can('expenses') then allowed=allowed||array['payment_status'];end if;
 when 'tasks' then permission='tasks';allowed=array['title','category','task_date','task_time','assigned_user_id','order_id','studio_piece_id','done','notes'];
 when 'events' then permission='calendar';allowed=array['title','category','event_date','event_time','assigned_user_id','order_id','studio_piece_id','notes'];
 when 'alterations' then permission='orders';allowed=array['order_id','issue','received_date','assigned_to','expected_date','status','notes'];if lm_private.can('expenses') then allowed=allowed||array['additional_cost'];end if;
 when 'inventory' then permission='owner';allowed=array['sku','name','colour','category','quantity','unit','reorder_level','cost','vendor','notes'];
 else raise insufficient_privilege using message='This record type is not available';end case;
 if not lm_private.can(permission) then raise insufficient_privilege using message='You do not have access to this action';end if;
 if p_table in ('tasks','events') and not lm_private.can('owner') then
  if p_id is not null then execute format('select created_by from public.%I where id=$1 and (created_by=$2 or assigned_user_id=$2)','lm_'||p_table) into row_owner using p_id,auth.uid();if row_owner is null then raise insufficient_privilege using message='This task is not assigned to you';end if;end if;
  if p_body?'assigned_user_id' and coalesce((p_body->>'assigned_user_id')::uuid,auth.uid())<>auth.uid() then raise insufficient_privilege using message='Only the owner can assign work to other team members';end if;
  if p_id is null then p_body=p_body||jsonb_build_object('assigned_user_id',auth.uid());end if;
 end if;
 if p_id is null then allowed=allowed||array['id'];else p_body=p_body-'id';end if;
 select array_agg(k order by k) into keys from jsonb_object_keys(p_body) k;
 if keys is null or not keys<@allowed then raise insufficient_privilege using message='One or more fields are not permitted';end if;
 select string_agg(format('%I',k),','),string_agg(format('%I=r.%I',k,k),',') into cols,updates from unnest(keys) k;
 if p_id is null then
  execute format('insert into public.%I (%s) select %s from jsonb_populate_record(null::public.%I,$1) r returning id','lm_'||p_table,cols,cols,'lm_'||p_table) into newid using p_body;
 else
  execute format('update public.%I t set %s from jsonb_populate_record(null::public.%I,$1) r where t.id=$2 returning t.id','lm_'||p_table,updates,'lm_'||p_table) into newid using p_body,p_id;
 end if;
 if newid is null then raise exception 'Record is unavailable';end if;
 return jsonb_build_object('id',newid,'saved',true);
end $$;

create function lm_private.save_order(p_order jsonb,p_items jsonb,p_id uuid default null,p_advance numeric default 0) returns jsonb language plpgsql security definer set search_path='' as $$
declare oid uuid;cid uuid;client_name text;item jsonb;iid uuid;ids uuid[]:='{}';total numeric;stage text;stages text[]:=array['New Order','Fabric','Cutting','Stitching','Embroidery / Handwork','Fitting','Alteration','Ready','Delivered'];isfinance boolean;olditem public.lm_order_items;begin
 if not lm_private.can('orders') then raise insufficient_privilege using message='Orders access required';end if;
 isfinance=lm_private.can('payments');
 if not isfinance and p_id is null then raise insufficient_privilege using message='Only staff with orders and payments access can create orders';end if;
 if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)<1 or jsonb_array_length(p_items)>100 then raise exception 'Add between 1 and 100 products';end if;
 if p_id is not null then perform 1 from public.lm_orders where id=p_id for update;if not found then raise exception 'Order unavailable';end if;oid=p_id;end if;
 if isfinance then
  cid=(p_order->>'customer_id')::uuid;select name into client_name from public.lm_customers where id=cid;if client_name is null then raise exception 'Choose a client';end if;
  if p_id is null then oid=coalesce((p_order->>'id')::uuid,gen_random_uuid());insert into public.lm_orders(id,reference,customer_id,customer_name,order_date,due_date,fitting_date,payment_due_date,product,quantity,amount,status,assigned_to,notes) values(oid,p_order->>'reference',cid,client_name,(p_order->>'order_date')::date,(p_order->>'due_date')::date,(p_order->>'fitting_date')::date,(p_order->>'payment_due_date')::date,'Products',1,0,'New Order',p_order->>'assigned_to',p_order->>'notes');end if;
  if (p_order->>'due_date')::date<(p_order->>'order_date')::date then raise exception 'Delivery date cannot precede order date';end if;
 else
  if p_order ?| array['amount','customer_id','reference','order_date','payment_due_date','advance','id','overall_state'] then raise insufficient_privilege using message='Financial and client changes require owner or accounts access';end if;
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
 if isfinance then update public.lm_orders set reference=p_order->>'reference',customer_id=cid,customer_name=client_name,order_date=(p_order->>'order_date')::date,due_date=(p_order->>'due_date')::date,fitting_date=(p_order->>'fitting_date')::date,payment_due_date=(p_order->>'payment_due_date')::date,amount=total,product=(select string_agg(name,' · ' order by position) from public.lm_order_items where order_id=oid),quantity=(select sum(quantity) from public.lm_order_items where order_id=oid),status=stage,assigned_to=p_order->>'assigned_to',notes=p_order->>'notes' where id=oid;
 else update public.lm_orders set fitting_date=(p_order->>'fitting_date')::date,due_date=(p_order->>'due_date')::date,status=stage,assigned_to=p_order->>'assigned_to',notes=p_order->>'notes' where id=oid;end if;
 if p_advance<0 then raise exception 'Advance cannot be negative';end if;
 if p_advance>0 then
  if not isfinance or p_id is not null then raise insufficient_privilege using message='Use Record payment for existing orders';end if;
  insert into public.lm_order_payments(order_id,payment_date,amount,kind,payment_mode) values(oid,(p_order->>'advance_date')::date,p_advance,'Advance',coalesce(p_order->>'payment_mode','UPI'));
 end if;
 return jsonb_build_object('id',oid,'saved',true);
end $$;

create function lm_private.manage_member(p_email text,p_role text,p_permissions text[],p_name text default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid;begin
 if not lm_private.can('owner') then raise insufficient_privilege using message='Only Muskan can manage team access';end if;
 if p_role not in ('production','team','accounts') or not p_permissions<@array['home','orders','clients','studio','production','tasks','calendar','payments','expenses','purchases','salaries'] then raise exception 'Choose a permitted team role and access';end if;
 select id into uid from auth.users where lower(email)=lower(trim(p_email)) and email_confirmed_at is not null;
 if uid is null then raise exception 'Create a confirmed login for this email in Supabase Authentication first';end if;
 if exists(select 1 from public.lm_staff where user_id=uid and role='owner') then raise exception 'The owner account cannot be changed';end if;
 insert into public.lm_staff(user_id,role,permissions,display_name) values(uid,p_role,p_permissions,p_name) on conflict(user_id) do update set role=excluded.role,permissions=excluded.permissions,display_name=excluded.display_name;
 return jsonb_build_object('saved',true);
end $$;
create function lm_private.remove_member(p_user_id uuid) returns void language plpgsql security definer set search_path='' as $$ begin
 if not lm_private.can('owner') then raise insufficient_privilege using message='Only Muskan can manage team access';end if;
 if exists(select 1 from public.lm_staff where user_id=p_user_id and role='owner') then raise exception 'The owner account cannot be removed';end if;
 update public.lm_tasks set assigned_user_id=null where assigned_user_id=p_user_id;
 update public.lm_events set assigned_user_id=null where assigned_user_id=p_user_id;
 delete from public.lm_staff where user_id=p_user_id;
end $$;

create function public.lm_workspace() returns jsonb language sql security invoker set search_path='' as $$ select lm_private.workspace(); $$;
create function public.lm_save_record(p_table text,p_body jsonb,p_id uuid default null) returns jsonb language sql security invoker set search_path='' as $$ select lm_private.save_record(p_table,p_body,p_id); $$;
create function public.lm_save_order(p_order jsonb,p_items jsonb,p_id uuid default null,p_advance numeric default 0) returns jsonb language sql security invoker set search_path='' as $$ select lm_private.save_order(p_order,p_items,p_id,p_advance); $$;
create function public.lm_manage_member(p_email text,p_role text,p_permissions text[],p_name text default null) returns jsonb language sql security invoker set search_path='' as $$ select lm_private.manage_member(p_email,p_role,p_permissions,p_name); $$;
create function public.lm_remove_member(p_user_id uuid) returns void language sql security invoker set search_path='' as $$ select lm_private.remove_member(p_user_id); $$;
do $$ declare schema_name text;function_signature text;begin
 foreach schema_name in array array['public','lm_private'] loop
  foreach function_signature in array case when schema_name='public' then array['lm_workspace()','lm_save_record(text,jsonb,uuid)','lm_save_order(jsonb,jsonb,uuid,numeric)','lm_manage_member(text,text,text[],text)','lm_remove_member(uuid)'] else array['workspace()','save_record(text,jsonb,uuid)','save_order(jsonb,jsonb,uuid,numeric)','manage_member(text,text,text[],text)','remove_member(uuid)'] end loop
   execute format('revoke all on function %I.%s from public,anon',schema_name,function_signature);
   execute format('grant execute on function %I.%s to authenticated',schema_name,function_signature);
  end loop;
 end loop;
end $$;
commit;
