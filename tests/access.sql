-- Run against project xybqwszhkbiucgextwog. Fixtures and all writes roll back.
begin;
insert into auth.users(id,email,email_confirmed_at) values
 ('10000000-0000-4000-8000-000000000001','production-test@example.invalid',now()),
 ('10000000-0000-4000-8000-000000000002','accounts-test@example.invalid',now()),
 ('10000000-0000-4000-8000-000000000003','team-test@example.invalid',now());
insert into public.lm_staff(user_id,role,permissions,display_name) values
 ('10000000-0000-4000-8000-000000000001','production',array['orders','production','studio','tasks','calendar'],'Test production'),
 ('10000000-0000-4000-8000-000000000002','accounts',array['payments','expenses','purchases'],'Test accounts'),
 ('10000000-0000-4000-8000-000000000003','team',array['tasks'],'Test team');
set local role authenticated;
select set_config('request.jwt.claim.sub','620ff01b-a3bb-4c91-9242-43a8ce4a49e4',true);
do $$ declare c uuid;oid uuid;result jsonb;items jsonb;begin
 result=public.lm_workspace();if not result?'home' or result#>>'{profile,role}'<>'owner' then raise exception 'Owner overview missing';end if;
 c=(public.lm_save_record('customers','{"name":"Rollback client"}',null)->>'id')::uuid;
 items='[{"name":"Boning top","quantity":1,"price":18500,"status":"Ready"},{"name":"Drape skirt","quantity":1,"price":12000,"status":"Stitching"},{"name":"Organza cape","quantity":1,"price":8500,"status":"Embroidery / Handwork"}]';
 oid=(public.lm_save_order(jsonb_build_object('reference','ROLLBACK-104','customer_id',c,'order_date','2026-10-06','due_date','2026-10-15','advance_date','2026-10-06','payment_mode','UPI'),items,null,10000)->>'id')::uuid;
 result=public.lm_workspace();
 if not exists(select 1 from jsonb_array_elements(result->'orders') o where o->>'id'=oid::text and (o->>'amount')::numeric=39000 and o->>'status'='Stitching') then raise exception 'Multi-product total / stage failed';end if;
 if (select count(*) from jsonb_array_elements(result->'order_items') i where i->>'order_id'=oid::text)<>3 then raise exception 'Products missing';end if;
 begin perform public.lm_save_record('order_payments',jsonb_build_object('order_id',oid,'amount',30000,'payment_date','2026-10-06','kind','Payment','payment_mode','UPI'),null);raise exception 'Overpayment allowed';exception when raise_exception then if sqlerrm<>'Payment exceeds the remaining order balance' then raise;end if;end;
 perform set_config('lm.test.order',oid::text,true);
 -- A studio piece never creates a client order.
 perform public.lm_save_record('studio_pieces','{"name":"Rollback sample","collection":"SCULPT EDIT","status":"Stitching"}',null);
 if jsonb_array_length(public.lm_workspace()->'orders')<>jsonb_array_length(result->'orders') then raise exception 'Studio piece became an order';end if;
 -- Owner can grant overview deliberately to an existing login.
 perform public.lm_manage_member('accounts-test@example.invalid','accounts',array['payments','expenses','purchases'],'Test accounts');
end $$;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
do $$ declare w jsonb;oid uuid;items jsonb;begin
 w=public.lm_workspace();
 if w ?| array['home','order_payments','expenses','purchases','members'] then raise exception 'Production financial data leaked';end if;
 if exists(select 1 from jsonb_array_elements(w->'orders') o where o ?| array['amount','paid','payment_due_date']) or exists(select 1 from jsonb_array_elements(w->'order_items') i where i?'price') then raise exception 'Production prices leaked';end if;
 begin perform amount from public.lm_orders;raise exception 'Direct table read allowed';exception when insufficient_privilege then null;end;
 begin perform public.lm_manage_member('production-test@example.invalid','production',array['home'],'Attack');raise exception 'Self promotion allowed';exception when insufficient_privilege then null;end;
 oid=current_setting('lm.test.order')::uuid;
 select jsonb_agg(i||jsonb_build_object('status','Fitting')) into items from jsonb_array_elements(w->'order_items') i where i->>'order_id'=oid::text;
 perform public.lm_save_order('{"due_date":"2026-10-15","fitting_date":"2026-10-10"}',items,oid,0);
 if not exists(select 1 from jsonb_array_elements(public.lm_workspace()->'orders') o where o->>'id'=oid::text and o->>'status'='Fitting') then raise exception 'Production update failed';end if;
 begin perform public.lm_save_order('{"due_date":"2026-10-15"}',jsonb_set(items,'{0,price}','1'),oid,0);raise exception 'Price mutation allowed';exception when insufficient_privilege then null;end;
 begin perform public.lm_save_record('expenses','{"description":"Attack","amount":1}',null);raise exception 'Expense mutation allowed';exception when insufficient_privilege then null;end;
 perform public.lm_save_record('tasks','{"title":"Production private task","task_date":"2026-10-06"}',null);
end $$;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',true);
do $$ declare w jsonb;begin
 w=public.lm_workspace();if not w?'order_payments' or not w?'expenses' or w?'home' or w?'members' then raise exception 'Accounts access incorrect';end if;
 begin perform public.lm_save_record('tasks','{"title":"Not allowed"}',null);raise exception 'Unassigned permission allowed';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000003',true);
do $$ declare w jsonb;begin
 w=public.lm_workspace();if w ?| array['orders','order_items','home','customers','order_payments','expenses'] then raise exception 'Team data leaked';end if;
 if exists(select 1 from jsonb_array_elements(w->'tasks') t where t->>'created_by'<>auth.uid()::text and t->>'assigned_user_id'<>auth.uid()::text) then raise exception 'Unrelated tasks leaked';end if;
 perform public.lm_save_record('tasks','{"title":"Team task","task_date":"2026-10-06"}',null);
 begin perform public.lm_save_record('tasks','{"title":"Other assignee","assigned_user_id":"10000000-0000-4000-8000-000000000001"}',null);raise exception 'Other user assignment allowed';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub','620ff01b-a3bb-4c91-9242-43a8ce4a49e4',true);
select public.lm_manage_member('accounts-test@example.invalid','accounts',array['payments','expenses','home'],'Test accounts');
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',true);
do $$ begin if not public.lm_workspace()?'home' then raise exception 'Explicit overview grant failed';end if;end $$;
select set_config('request.jwt.claim.sub','620ff01b-a3bb-4c91-9242-43a8ce4a49e4',true);
select public.lm_remove_member('10000000-0000-4000-8000-000000000002');
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',true);
do $$ begin begin perform public.lm_workspace();raise exception 'Revoked user retains access';exception when insufficient_privilege then null;end;end $$;
reset role;
select 'Owner, production, accounts, team, explicit grants and revocation checks passed; fixtures rolled back' as result;
rollback;
