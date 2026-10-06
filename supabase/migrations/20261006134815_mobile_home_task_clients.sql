begin;
alter table public.lm_tasks add column customer_id uuid references public.lm_customers(id);
create index lm_tasks_customer_idx on public.lm_tasks(customer_id);
create or replace function lm_private.save_record(p_table text,p_body jsonb,p_id uuid default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare allowed text[];permission text;keys text[];cols text;updates text;newid uuid; row_owner uuid;client_id uuid;begin
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
 when 'tasks' then permission='tasks';allowed=array['customer_id','title','category','task_date','task_time','assigned_user_id','order_id','studio_piece_id','done','notes'];
 when 'events' then permission='calendar';allowed=array['title','category','event_date','event_time','assigned_user_id','order_id','studio_piece_id','notes'];
 when 'alterations' then permission='orders';allowed=array['order_id','issue','received_date','assigned_to','expected_date','status','notes'];if lm_private.can('expenses') then allowed=allowed||array['additional_cost'];end if;
 when 'inventory' then permission='owner';allowed=array['sku','name','colour','category','quantity','unit','reorder_level','cost','vendor','notes'];
 else raise insufficient_privilege using message='This record type is not available';end case;
 if not lm_private.can(permission) then raise insufficient_privilege using message='You do not have access to this action';end if;
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
 return jsonb_build_object('id',newid,'saved',true);
end $$;
commit;
