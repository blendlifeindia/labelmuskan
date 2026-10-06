-- Synthetic fixtures are rolled back. Approved project only.
begin;
insert into auth.users(id,email,email_confirmed_at) values('40000000-0000-4000-8000-000000000001','invoice-accounts@example.invalid',now());
insert into public.lm_staff(user_id,role,permissions) values('40000000-0000-4000-8000-000000000001','accounts',array['payments','expenses','purchases']);
set local role authenticated;
select set_config('request.jwt.claim.sub','620ff01b-a3bb-4c91-9242-43a8ce4a49e4',true);
do $$ declare c uuid;oid uuid;oid2 uuid;v jsonb;num text;begin
 c=(public.lm_save_record('customers','{"name":"Invoice rollback client","phone":"9000000000","address":"Synthetic address"}',null)->>'id')::uuid;
 oid=(public.lm_save_order(jsonb_build_object('reference','ROLLBACK-INVOICE','customer_id',c,'order_date','2026-10-06','advance_date','2026-10-06','payment_mode','UPI'),'[{"name":"Top","quantity":2,"price":1000,"status":"New Order"},{"name":"Skirt","quantity":1,"price":3000,"status":"New Order"}]',null,1000)->>'id')::uuid;
 perform set_config('test.invoice_id',oid::text,true);
 v=public.lm_invoice(oid);num=v->'order'->>'invoice_number';
 if num is null or jsonb_array_length(v->'items')<>2 or (v->'order'->>'amount')::numeric<>5000 then raise exception 'Identity or products incorrect';end if;
 perform public.lm_save_record('customers','{"name":"Updated rollback client"}',c);
 perform public.lm_save_record('order_payments',jsonb_build_object('order_id',oid,'payment_date','2026-10-06','amount',500,'kind','Payment','payment_mode','Cash'),null);
 v=public.lm_invoice(oid);
 if v->'client'->>'name'<>'Updated rollback client' or (select sum((p->>'amount')::numeric) from jsonb_array_elements(v->'payments') p)<>1500 then raise exception 'Live client/payment snapshot stale';end if;
 perform public.lm_save_order(jsonb_build_object('reference','ROLLBACK-INVOICE','customer_id',c,'order_date','2026-10-06'),'[{"name":"Updated Top","quantity":2,"price":1200,"status":"New Order"},{"name":"Skirt","quantity":1,"price":3000,"status":"New Order"}]',oid,0);
 v=public.lm_invoice(oid);
 if v->'order'->>'invoice_number'<>num or (v->'order'->>'amount')::numeric<>5400 then raise exception 'Order edit changed identity or left stale prices';end if;
 oid2=(public.lm_save_order(jsonb_build_object('reference','ROLLBACK-INVOICE-2','customer_id',c,'order_date','2026-10-06'),'[{"name":"Dress","quantity":1,"price":1000,"status":"New Order"}]',null,0)->>'id')::uuid;
 if public.lm_invoice(oid2)->'order'->>'invoice_number'=num then raise exception 'Duplicate invoice number';end if;
 if public.lm_invoice(oid)->'order'->>'invoice_number'<>num then raise exception 'Invoice identity changed';end if;
end $$;
select set_config('request.jwt.claim.sub','40000000-0000-4000-8000-000000000001',true);
do $$ begin
 begin perform public.lm_invoice(current_setting('test.invoice_id')::uuid);raise exception 'Accounts without client permission can invoice';exception when insufficient_privilege then null;end;
 if has_function_privilege('anon','public.lm_invoice(uuid)','execute') then raise exception 'Anonymous invoice access';end if;
end $$;
select 'Invoice identity, latest client/payments, products and access checks passed' result;
rollback;
