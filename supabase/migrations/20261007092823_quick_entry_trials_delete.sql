-- Approved Label Muskan project only. Deletion is recoverable, never a purge.
alter table public.lm_orders add column trials text check(length(trials)<=200);
alter table public.lm_expenses alter column payment_mode drop not null, alter column payment_mode drop default;

create function lm_private.save_expense_batch(p_rows jsonb,p_date text default null,p_paid_by text default null,p_mode text default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare row jsonb;result jsonb;ids jsonb:='[]';day date;mode text;begin
 if auth.uid() is null or not lm_private.is_staff() or not lm_private.can('expenses') then raise insufficient_privilege using message='Expense access required';end if;
 if jsonb_typeof(p_rows) is distinct from 'array' or jsonb_array_length(p_rows) not between 1 and 100 then raise exception 'Enter between 1 and 100 expenses';end if;
 day:=coalesce(nullif(p_date,'')::date,(now() at time zone 'Asia/Kolkata')::date);
 mode:=nullif(p_mode,'');if mode is not null and mode not in ('Cash','UPI','Bank transfer','Card') then raise exception 'Choose a supported payment mode';end if;
 for row in select value from jsonb_array_elements(p_rows) loop
  if length(trim(coalesce(row->>'description','')))=0 or coalesce((row->>'amount')::numeric,0)<=0 then raise exception 'Each expense needs a description and a positive amount';end if;
  if row->>'category' is null or row->>'category' not in ('Salary','Karigar','Fabric','Dye','Packaging','Studio','Marketing/PR','Courier','Miscellaneous') then raise exception 'Choose an expense category';end if;
  result:=lm_private.save_record('expenses',jsonb_build_object('expense_date',day,'description',trim(row->>'description'),'category',row->>'category','amount',round((row->>'amount')::numeric,2),'paid_by',nullif(trim(p_paid_by),''),'payment_mode',mode,'status','Paid'),null);
  ids:=ids||jsonb_build_array(result->>'id');
 end loop;
 return jsonb_build_object('saved',true,'ids',ids,'count',jsonb_array_length(ids));
end $$;
create function public.lm_save_expense_batch(p_rows jsonb,p_date text default null,p_paid_by text default null,p_mode text default null) returns jsonb language sql security invoker set search_path='' as $$select lm_private.save_expense_batch(p_rows,p_date,p_paid_by,p_mode);$$;

create table lm_private.deleted_entries(id uuid primary key default gen_random_uuid(),deleted_at timestamptz not null default now(),deleted_by uuid not null references auth.users(id),root_table text not null,root_id uuid not null,label text not null,records jsonb not null,restored_at timestamptz);
alter table lm_private.deleted_entries enable row level security;
revoke all on lm_private.deleted_entries from public,anon,authenticated;
create policy owner_deleted_entries on lm_private.deleted_entries to authenticated using((select lm_private.can('owner'))) with check((select lm_private.can('owner')));

-- Ordered children before parents; only these operational tables can be removed/restored.
create function lm_private.delete_tables() returns text[] language sql immutable set search_path='' as $$select array['jobs','tasks','events','alterations','order_payments','purchase_payments','salary_payments','salary_payouts','order_items','expenses','purchases','orders','salary_profiles','salaries','studio_pieces','customers','inventory','influencer_marketing'];$$;
create function lm_private.delete_snapshot(p_table text,p_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare records jsonb:='{}';rows jsonb;edge record;changed boolean;table_name text;mirror text;begin
 if auth.uid() is null or not lm_private.is_staff() or not lm_private.can('owner') then raise insufficient_privilege using message='Only Muskan can delete or restore studio records';end if;
 if p_table is null or not p_table=any(lm_private.delete_tables()) then raise insufficient_privilege using message='This record type cannot be deleted';end if;
 execute format('select coalesce(jsonb_agg(to_jsonb(t) order by t.id),''[]''::jsonb) from public.%I t where id=$1','lm_'||p_table) into rows using p_id;
 if jsonb_array_length(rows)=0 then raise exception 'Record is unavailable';end if;
 records:=jsonb_build_object(p_table,rows);
 loop
  changed:=false;
  for edge in select c.relname child,p.relname parent,a.attname column_name from pg_catalog.pg_constraint fk join pg_catalog.pg_class c on c.oid=fk.conrelid join pg_catalog.pg_namespace cn on cn.oid=c.relnamespace join pg_catalog.pg_class p on p.oid=fk.confrelid join pg_catalog.pg_namespace pn on pn.oid=p.relnamespace join pg_catalog.pg_attribute a on a.attrelid=c.oid and a.attnum=fk.conkey[1] where fk.contype='f' and cn.nspname='public' and pn.nspname='public' and c.relname=any(array(select 'lm_'||x from unnest(lm_private.delete_tables()) x)) and p.relname=any(array(select 'lm_'||x from unnest(lm_private.delete_tables()) x)) loop
   if not records?substring(edge.parent from 4) then continue;end if;
   execute format('select coalesce(jsonb_agg(to_jsonb(t) order by t.id),''[]''::jsonb) from public.%I t where %I in(select (r->>''id'')::uuid from jsonb_array_elements($1) r) and id not in(select (r->>''id'')::uuid from jsonb_array_elements($2) r)',edge.child,edge.column_name) into rows using records->substring(edge.parent from 4),coalesce(records->substring(edge.child from 4),'[]');
   if jsonb_array_length(rows)>0 then records:=jsonb_set(records,array[substring(edge.child from 4)],coalesce(records->substring(edge.child from 4),'[]')||rows);changed:=true;end if;
  end loop;
  -- Old payroll receipts were copied once to the actual-payment ledger with the same ID.
  foreach table_name in array array['salary_payments','salary_payouts'] loop
   mirror:=case table_name when 'salary_payments' then 'salary_payouts' else 'salary_payments' end;
   if records?table_name then
    execute format('select coalesce(jsonb_agg(to_jsonb(t) order by t.id),''[]''::jsonb) from public.%I t where id in(select (r->>''id'')::uuid from jsonb_array_elements($1) r) and id not in(select (r->>''id'')::uuid from jsonb_array_elements($2) r)','lm_'||mirror) into rows using records->table_name,coalesce(records->mirror,'[]');
    if jsonb_array_length(rows)>0 then records:=jsonb_set(records,array[mirror],coalesce(records->mirror,'[]')||rows);changed:=true;end if;
   end if;
  end loop;
  exit when not changed;
 end loop;
 return records;
end $$;
create function lm_private.delete_preview(p_table text,p_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare records jsonb;root jsonb;begin
 records:=lm_private.delete_snapshot(p_table,p_id);root:=records->p_table->0;
 return jsonb_build_object('label',coalesce(root->>'reference',root->>'name',root->>'staff_name',root->>'item',root->>'description',root->>'title',root->>'influencer_name',root->>'karigar',root->>'issue','Entry'),'token',md5(records::text),'counts',(select jsonb_object_agg(key,jsonb_array_length(value)) from jsonb_each(records)));
end $$;
create function lm_private.delete_record(p_table text,p_id uuid,p_token text) returns jsonb language plpgsql security definer set search_path='' as $$
declare records jsonb;preview jsonb;table_name text;aid uuid;begin
 if auth.uid() is null or not lm_private.is_staff() or not lm_private.can('owner') then raise insufficient_privilege using message='Only Muskan can delete studio records';end if;
 -- Serialize the short deletion transaction against new linked records and payments.
 foreach table_name in array lm_private.delete_tables() loop execute format('lock table public.%I in share row exclusive mode','lm_'||table_name);end loop;
 preview:=lm_private.delete_preview(p_table,p_id);if p_token is distinct from preview->>'token' then raise exception 'This entry changed. Review Delete again before confirming.';end if;
 records:=lm_private.delete_snapshot(p_table,p_id);
 insert into lm_private.deleted_entries(deleted_by,root_table,root_id,label,records) values(auth.uid(),p_table,p_id,preview->>'label',records) returning id into aid;
 foreach table_name in array lm_private.delete_tables() loop
  if records?table_name then execute format('delete from public.%I where id in(select (r->>''id'')::uuid from jsonb_array_elements($1) r)','lm_'||table_name) using records->table_name;end if;
 end loop;
 return jsonb_build_object('saved',true,'archive_id',aid);
end $$;
create function lm_private.deleted_list() returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if auth.uid() is null or not lm_private.is_staff() or not lm_private.can('owner') then raise insufficient_privilege using message='Only Muskan can view deleted entries';end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('id',id,'label',label,'root_table',root_table,'deleted_at',deleted_at,'count',(select sum(jsonb_array_length(value)) from jsonb_each(records))) order by deleted_at desc),'[]') from lm_private.deleted_entries where restored_at is null);
end $$;
create function lm_private.restore_record(p_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare archive lm_private.deleted_entries;table_name text;row jsonb;i integer;names text[]:=lm_private.delete_tables();begin
 if auth.uid() is null or not lm_private.is_staff() or not lm_private.can('owner') then raise insufficient_privilege using message='Only Muskan can restore studio records';end if;
 select * into archive from lm_private.deleted_entries where id=p_id and restored_at is null for update;if not found then raise exception 'Deleted entry is unavailable or already restored';end if;
 for i in reverse cardinality(names)..1 loop
  table_name:=names[i];
  for row in select value from jsonb_array_elements(coalesce(archive.records->table_name,'[]')) loop
   execute format('insert into public.%I select * from jsonb_populate_record(null::public.%I,$1)','lm_'||table_name,'lm_'||table_name) using row;
  end loop;
 end loop;
 update lm_private.deleted_entries set restored_at=now() where id=p_id;
 return jsonb_build_object('saved',true);
 exception when unique_violation then raise exception 'A matching entry already exists. Rename that entry before restoring this one.';
end $$;
create function public.lm_delete_preview(p_table text,p_id uuid) returns jsonb language sql security invoker set search_path='' as $$select lm_private.delete_preview(p_table,p_id);$$;
create function public.lm_delete_record(p_table text,p_id uuid,p_token text) returns jsonb language sql security invoker set search_path='' as $$select lm_private.delete_record(p_table,p_id,p_token);$$;
create function public.lm_deleted_list() returns jsonb language sql security invoker set search_path='' as $$select lm_private.deleted_list();$$;
create function public.lm_restore_record(p_id uuid) returns jsonb language sql security invoker set search_path='' as $$select lm_private.restore_record(p_id);$$;
revoke all on function lm_private.delete_tables(),lm_private.delete_snapshot(text,uuid),lm_private.delete_preview(text,uuid),lm_private.delete_record(text,uuid,text),lm_private.deleted_list(),lm_private.restore_record(uuid),lm_private.save_expense_batch(jsonb,text,text,text),public.lm_delete_preview(text,uuid),public.lm_delete_record(text,uuid,text),public.lm_deleted_list(),public.lm_restore_record(uuid),public.lm_save_expense_batch(jsonb,text,text,text) from public,anon;
grant execute on function lm_private.delete_tables(),lm_private.delete_snapshot(text,uuid),lm_private.delete_preview(text,uuid),lm_private.delete_record(text,uuid,text),lm_private.deleted_list(),lm_private.restore_record(uuid),lm_private.save_expense_batch(jsonb,text,text,text),public.lm_delete_preview(text,uuid),public.lm_delete_record(text,uuid,text),public.lm_deleted_list(),public.lm_restore_record(uuid),public.lm_save_expense_batch(jsonb,text,text,text) to authenticated;

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
  if p_id is null then oid=coalesce((p_order->>'id')::uuid,gen_random_uuid());insert into public.lm_orders(id,reference,customer_id,customer_name,order_date,due_date,fitting_date,trials,payment_due_date,product,quantity,amount,status,assigned_to,notes) values(oid,p_order->>'reference',cid,client_name,(p_order->>'order_date')::date,(p_order->>'due_date')::date,nullif(p_order->>'fitting_date','')::date,nullif(p_order->>'trials',''),(p_order->>'payment_due_date')::date,'Products',1,0,'New Order',p_order->>'assigned_to',p_order->>'notes');end if;
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
 if isfinance then update public.lm_orders set reference=p_order->>'reference',customer_id=cid,customer_name=client_name,order_date=(p_order->>'order_date')::date,due_date=(p_order->>'due_date')::date,fitting_date=case when p_order?'fitting_date' then nullif(p_order->>'fitting_date','')::date else fitting_date end,trials=case when p_order?'trials' then nullif(p_order->>'trials','') else trials end,payment_due_date=(p_order->>'payment_due_date')::date,payment_mode=case when p_order?'payment_mode' then chosen_mode else payment_mode end,invoice_date=coalesce(nullif(p_order->>'invoice_date','')::date,(p_order->>'order_date')::date),amount=total,product=(select string_agg(name,' · ' order by position) from public.lm_order_items where order_id=oid),quantity=(select sum(quantity) from public.lm_order_items where order_id=oid),status=stage,assigned_to=p_order->>'assigned_to',notes=p_order->>'notes' where id=oid;
 else update public.lm_orders set fitting_date=case when p_order?'fitting_date' then nullif(p_order->>'fitting_date','')::date else fitting_date end,trials=case when p_order?'trials' then nullif(p_order->>'trials','') else trials end,due_date=(p_order->>'due_date')::date,status=stage,assigned_to=p_order->>'assigned_to',notes=p_order->>'notes' where id=oid;end if;
 if isfinance and p_id is not null and p_order?'payment_mode' then
  update public.lm_order_payments set payment_mode=chosen_mode where id=(select id from public.lm_order_payments where order_id=oid and kind='Advance' and not voided order by created_at,id limit 1);
 end if;
 if p_advance<0 then raise exception 'Advance cannot be negative';end if;
 if p_advance>0 then
  if not isfinance or p_id is not null then raise insufficient_privilege using message='Use Record payment for existing orders';end if;
  insert into public.lm_order_payments(order_id,payment_date,amount,kind,payment_mode) values(oid,(p_order->>'advance_date')::date,p_advance,'Advance',chosen_mode);
 end if;
 return jsonb_build_object('id',oid,'saved',true);
end $function$;


CREATE OR REPLACE FUNCTION lm_private.save_record(p_table text, p_body jsonb, p_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
 if p_table='expenses' and (not p_body?'expense_date' or nullif(p_body->>'expense_date','') is null) then p_body:=p_body||jsonb_build_object('expense_date',coalesce((select expense_date from public.lm_expenses where id=p_id),(now() at time zone 'Asia/Kolkata')::date));end if;
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
end $function$;

