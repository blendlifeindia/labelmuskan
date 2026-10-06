begin;
create table public.lm_salary_profiles(id uuid primary key default gen_random_uuid(),created_at timestamptz not null default now(),staff_name text not null check(length(trim(staff_name))>0),amount numeric not null check(amount>=0),frequency text not null check(frequency in ('Weekly','Monthly')),payment_day text,active boolean not null default true,notes text);
create unique index lm_salary_profile_name_frequency on public.lm_salary_profiles(lower(staff_name),frequency);
create table public.lm_salary_payouts(id uuid primary key default gen_random_uuid(),created_at timestamptz not null default now(),profile_id uuid not null references public.lm_salary_profiles(id),payment_date date not null,amount numeric not null check(amount>0),kind text not null default 'Salary' check(kind in ('Salary','Advance')),payment_mode text not null default 'Other',voided boolean not null default false,notes text);
create index on public.lm_salary_payouts(profile_id,payment_date);
insert into public.lm_salary_profiles(staff_name,amount,frequency,payment_day,notes) select distinct on(lower(staff_name),frequency) staff_name,greatest(0,salary-deduction),frequency,case when frequency='Weekly' then 'Saturday' else null end,notes from public.lm_salaries order by lower(staff_name),frequency,period_start desc,created_at desc;
insert into public.lm_salary_payouts(id,created_at,profile_id,payment_date,amount,kind,payment_mode,voided,notes) select p.id,p.created_at,sp.id,p.payment_date,p.amount,p.kind,p.payment_mode,p.voided,p.notes from public.lm_salary_payments p join public.lm_salaries s on s.id=p.salary_id join public.lm_salary_profiles sp on lower(sp.staff_name)=lower(s.staff_name) and sp.frequency=s.frequency;
create table public.lm_purchase_payments(id uuid primary key default gen_random_uuid(),created_at timestamptz not null default now(),purchase_id uuid not null references public.lm_purchases(id),payment_date date not null,amount numeric not null check(amount>0),payment_mode text not null default 'Other',voided boolean not null default false,notes text);
create index on public.lm_purchase_payments(purchase_id,payment_date);
insert into public.lm_purchase_payments(purchase_id,payment_date,amount,notes) select id,purchase_date,amount,'Opening payment from previously marked Paid purchase' from public.lm_purchases where status='Paid' and amount>0;
do $$ declare t text;begin foreach t in array array['lm_salary_profiles','lm_salary_payouts','lm_purchase_payments'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from public,anon,authenticated',t);
 execute format('create policy owner_only on public.%I for all to authenticated using ((select lm_private.can(''owner''))) with check ((select lm_private.can(''owner'')))',t);
end loop;end $$;
create function lm_private.validate_purchase_payment() returns trigger language plpgsql security invoker set search_path='' as $$ declare price numeric;paid numeric;begin
 select amount into price from public.lm_purchases where id=new.purchase_id for update;if new.voided then return new;end if;
 select coalesce(sum(amount),0) into paid from public.lm_purchase_payments where purchase_id=new.purchase_id and not voided and id<>new.id;
 if paid+new.amount>price then raise exception 'Payment exceeds the remaining purchase balance';end if;return new;end $$;
create trigger purchase_payment_cap before insert or update on public.lm_purchase_payments for each row execute function lm_private.validate_purchase_payment();
create function lm_private.validate_purchase_value() returns trigger language plpgsql security invoker set search_path='' as $$ begin
 if new.amount<(select coalesce(sum(amount),0) from public.lm_purchase_payments where purchase_id=new.id and not voided) then raise exception 'Purchase amount cannot be lower than payments already recorded';end if;return new;end $$;
create trigger purchase_value_cap before update on public.lm_purchases for each row execute function lm_private.validate_purchase_value();
revoke all on function lm_private.validate_purchase_payment(),lm_private.validate_purchase_value() from public,anon,authenticated;
create or replace function lm_private.save_record(p_table text,p_body jsonb,p_id uuid default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare allowed text[];permission text;keys text[];cols text;updates text;newid uuid; row_owner uuid;client_id uuid;initialpaid numeric:=0;paiddate date;begin
 if auth.uid() is null or not lm_private.is_staff() then raise insufficient_privilege using message='Studio access required';end if;
 case p_table
 when 'customers' then permission='clients';allowed=array['name','phone','email','instagram','city','address','measurements','measurement_date','preferences','alteration_notes','notes'];
 when 'expenses' then permission='expenses';allowed=array['expense_date','description','category','amount','paid_by','payment_mode','order_id','notes'];
 when 'purchases' then permission='purchases';allowed=array['purchase_date','vendor','item','category','quantity','amount','order_id','studio_piece_id','collection','status','notes'];
 when 'salary_profiles' then permission='salaries';allowed=array['staff_name','amount','frequency','payment_day','active','notes'];
 when 'salary_payouts' then permission='salaries';allowed=case when p_id is null then array['profile_id','payment_date','amount','kind','payment_mode','notes'] else array['voided','notes'] end;
 when 'purchase_payments' then permission='purchases';allowed=case when p_id is null then array['purchase_id','payment_date','amount','payment_mode','notes'] else array['voided','notes'] end;
 when 'salaries' then permission='salaries';allowed=array['staff_name','salary','frequency','period_start','period_end','deduction','notes'];
 when 'order_payments' then permission='payments';allowed=case when p_id is null then array['order_id','payment_date','amount','kind','payment_mode','notes'] else array['voided','notes'] end;
 when 'salary_payments' then permission='salaries';allowed=case when p_id is null then array['salary_id','payment_date','amount','kind','payment_mode','notes'] else array['voided','notes'] end;
 when 'studio_pieces' then permission='studio';allowed=array['name','collection','kind','description','fabric','quantity','due_date','shoot_date','status','assigned_to','notes'];
 when 'jobs' then permission='production';allowed=array['karigar','work','kind','order_item_id','studio_piece_id','given_date','due_date','status','notes'];if lm_private.can('expenses') then allowed=allowed||array['payment_status'];end if;
 when 'tasks' then permission='tasks';allowed=array['customer_id','title','category','task_date','task_time','assigned_user_id','order_id','studio_piece_id','done','notes'];
 when 'events' then permission='calendar';allowed=array['title','category','event_date','event_time','assigned_user_id','order_id','studio_piece_id','notes'];
 when 'alterations' then permission='orders';allowed=array['order_id','issue','received_date','assigned_to','expected_date','status','notes'];if lm_private.can('expenses') then allowed=allowed||array['additional_cost'];end if;
 when 'inventory' then permission='owner';allowed=array['sku','name','colour','category','quantity','unit','reorder_level','cost','vendor','notes'];
 else raise insufficient_privilege using message='This record type is not available';end case;
 if not lm_private.can(permission) then raise insufficient_privilege using message='You do not have access to this action';end if;
 if p_table='purchases' then
  if p_id is null then
   initialpaid=case p_body->>'status' when 'Paid' then (p_body->>'amount')::numeric when 'Part paid' then coalesce((p_body->>'paid_now')::numeric,0) else 0 end;
   paiddate=coalesce((p_body->>'paid_date')::date,(p_body->>'purchase_date')::date);
   if p_body->>'status'='Part paid' and (initialpaid<=0 or initialpaid>=(p_body->>'amount')::numeric) then raise exception 'Enter the partial payment amount';end if;
  end if;
  p_body=p_body-array['paid_now','paid_date'];
 end if;
 if p_table='tasks' and nullif(p_body->>'order_id','') is not null then
  select customer_id into client_id from public.lm_orders where id=(p_body->>'order_id')::uuid;
  if nullif(p_body->>'customer_id','') is not null and (p_body->>'customer_id')::uuid is distinct from client_id then raise exception 'Choose the client attached to this order';end if;
  p_body=p_body||jsonb_build_object('customer_id',client_id);
 end if;
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
 if p_table='purchases' and p_id is null and initialpaid>0 then insert into public.lm_purchase_payments(purchase_id,payment_date,amount) values(newid,paiddate,initialpaid);end if;
 return jsonb_build_object('id',newid,'saved',true);
end $$;
create or replace function lm_private.workspace() returns jsonb language plpgsql stable security definer set search_path='' as $$
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
end $$;
create function lm_private.month_money(p_month text) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare firstday date;lastday date;sales numeric;collected numeric;outstanding numeric;payroll numeric;purchases numeric;expenses numeric;total numeric;begin
 if not lm_private.can('home') then raise insufficient_privilege using message='Business totals require explicit owner permission';end if;
 if p_month is null or p_month!~'^\d{4}-(0[1-9]|1[0-2])$' then raise exception 'Choose a month';end if;
 firstday=(p_month||'-01')::date;lastday=(firstday+interval '1 month - 1 day')::date;
 select coalesce(sum(amount),0) into sales from public.lm_orders where status<>'Cancelled' and order_date between firstday and lastday;
 select coalesce(sum(amount),0) into collected from public.lm_order_payments where not voided and payment_date between firstday and lastday;
 select coalesce(sum(greatest(0,o.amount-coalesce((select sum(p.amount) from public.lm_order_payments p where p.order_id=o.id and not p.voided and p.payment_date<=lastday),0))),0) into outstanding from public.lm_orders o where o.status<>'Cancelled' and o.order_date<=lastday;
 payroll=coalesce((select sum(amount) from public.lm_salary_payouts where not voided and payment_date between firstday and lastday),0)+coalesce((select sum(amount) from public.lm_expenses where category='Salary' and expense_date between firstday and lastday),0);
 select coalesce(sum(amount),0) into purchases from public.lm_purchase_payments where not voided and payment_date between firstday and lastday;
 select coalesce(sum(amount),0) into expenses from public.lm_expenses where category<>'Salary' and expense_date between firstday and lastday;
 total=payroll+purchases+expenses;
 return jsonb_build_object('sales',sales,'collected',collected,'outstanding',outstanding,'salaries',payroll,'purchases',purchases,'other_expenses',expenses,'total_out',total,'net',collected-total);
end $$;
create function public.lm_month_money(p_month text) returns jsonb language sql security invoker set search_path='' as $$ select lm_private.month_money(p_month); $$;
revoke all on function lm_private.month_money(text),public.lm_month_money(text) from public,anon;
grant execute on function lm_private.month_money(text),public.lm_month_money(text) to authenticated;
commit;
