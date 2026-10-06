begin;
alter table public.lm_expenses add column voided boolean not null default false;
alter table public.lm_expenses drop constraint lm_expenses_status_check;
update public.lm_expenses set status='Pending' where status='Unpaid';
alter table public.lm_expenses add constraint lm_expenses_status_check check(status in ('Paid','Pending'));
alter table public.lm_purchases add column voided boolean not null default false;
alter table public.lm_salary_profiles add column job_role text;
create or replace function lm_private.save_record(p_table text,p_body jsonb,p_id uuid default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare allowed text[];permission text;keys text[];cols text;updates text;newid uuid; row_owner uuid;client_id uuid;initialpaid numeric:=0;paiddate date;begin
 if auth.uid() is null or not lm_private.is_staff() then raise insufficient_privilege using message='Studio access required';end if;
 case p_table
 when 'customers' then permission='clients';allowed=array['name','phone','email','instagram','city','address','measurements','measurement_date','preferences','alteration_notes','notes'];
 when 'expenses' then permission='expenses';allowed=array['expense_date','description','category','amount','paid_by','payment_mode','order_id','notes','status'];
 when 'purchases' then permission='purchases';allowed=array['purchase_date','vendor','item','category','quantity','amount','order_id','studio_piece_id','collection','status','notes'];
 when 'salary_profiles' then permission='salaries';allowed=array['staff_name','amount','frequency','payment_day','active','notes','job_role'];
 when 'salary_payouts' then permission='salaries';allowed=case when p_id is null then array['profile_id','payment_date','amount','kind','payment_mode','notes'] else array['voided','notes','payment_date','amount','payment_mode'] end;
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
create or replace function lm_private.month_money(p_month text) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare firstday date;lastday date;sales numeric;collected numeric;outstanding numeric;payroll numeric;purchases numeric;expenses numeric;total numeric;begin
 if not lm_private.can('home') then raise insufficient_privilege using message='Business totals require explicit owner permission';end if;
 if p_month is null or p_month!~'^\d{4}-(0[1-9]|1[0-2])$' then raise exception 'Choose a month';end if;
 firstday=(p_month||'-01')::date;lastday=(firstday+interval '1 month - 1 day')::date;
 select coalesce(sum(amount),0) into sales from public.lm_orders where status<>'Cancelled' and order_date between firstday and lastday;
 select coalesce(sum(amount),0) into collected from public.lm_order_payments where not voided and payment_date between firstday and lastday;
 select coalesce(sum(greatest(0,o.amount-coalesce((select sum(p.amount) from public.lm_order_payments p where p.order_id=o.id and not p.voided and p.payment_date<=lastday),0))),0) into outstanding from public.lm_orders o where o.status<>'Cancelled' and o.order_date<=lastday;
 payroll=coalesce((select sum(amount) from public.lm_salary_payouts where not voided and payment_date between firstday and lastday),0)+coalesce((select sum(amount) from public.lm_expenses where not voided and status='Paid' and category='Salary' and expense_date between firstday and lastday),0);
 select coalesce(sum(pp.amount),0) into purchases from public.lm_purchase_payments pp join public.lm_purchases p on p.id=pp.purchase_id where not pp.voided and not p.voided and pp.payment_date between firstday and lastday;
 select coalesce(sum(amount),0) into expenses from public.lm_expenses where not voided and status='Paid' and category<>'Salary' and expense_date between firstday and lastday;
 total=payroll+purchases+expenses;
 return jsonb_build_object('sales',sales,'collected',collected,'outstanding',outstanding,'salaries',payroll,'purchases',purchases,'other_expenses',expenses,'total_out',total,'net',collected-total);
end $$;

create function lm_private.set_expense_void(p_table text,p_id uuid,p_voided boolean) returns jsonb language plpgsql security definer set search_path='' as $$
declare permission text;changed uuid;begin
 if auth.uid() is null or not lm_private.is_staff() then raise insufficient_privilege using message='Studio access required';end if;
 permission=case p_table when 'expenses' then 'expenses' when 'purchases' then 'purchases' when 'salary_payouts' then 'salaries' else null end;
 if permission is null or not lm_private.can(permission) then raise insufficient_privilege using message='Expense access required';end if;
 if p_voided is null then raise exception 'Choose void or restore';end if;
 execute format('update public.%I set voided=$1 where id=$2 returning id','lm_'||p_table) into changed using p_voided,p_id;
 if changed is null then raise exception 'Entry unavailable';end if;
 return jsonb_build_object('saved',true,'id',changed);
end $$;
create function public.lm_set_expense_void(p_table text,p_id uuid,p_voided boolean) returns jsonb language sql security invoker set search_path='' as $$select lm_private.set_expense_void(p_table,p_id,p_voided)$$;
revoke all on function lm_private.set_expense_void(text,uuid,boolean),public.lm_set_expense_void(text,uuid,boolean) from public,anon,authenticated;
grant execute on function lm_private.set_expense_void(text,uuid,boolean),public.lm_set_expense_void(text,uuid,boolean) to authenticated;
commit;
