-- Runs checks in a rolled-back transaction; leaves no business records.
begin;
select set_config('request.jwt.claim.sub',(select user_id::text from public.lm_staff limit 1),true);
set local role authenticated;
do $$ declare o public.lm_orders; sid uuid; pid uuid; begin
 select * into o from public.lm_create_order('{"reference":"__test_order__","order_date":"2026-10-05","due_date":"2026-10-15","product":"Test outfit","quantity":1,"amount":48000,"status":"Cutting","advance_date":"2026-10-05"}'::jsonb,12000,'{"name":"__test_client__"}'::jsonb);
 if (select sum(amount) from public.lm_order_payments where order_id=o.id)<>12000 then raise exception 'Advance missing'; end if;
 begin
  insert into public.lm_order_payments(order_id,payment_date,amount) values(o.id,'2026-10-05',40000);
  raise exception 'Overpayment allowed';
 exception when raise_exception then if sqlerrm<>'Payment exceeds the remaining order balance' then raise; end if; end;
 insert into public.lm_order_payments(order_id,payment_date,amount) values(o.id,'2026-10-06',18000) returning id into pid;
 update public.lm_order_payments set voided=true where id=pid;
 begin
  update public.lm_orders set amount=10000 where id=o.id;
  raise exception 'Price below receipts allowed';
 exception when raise_exception then if sqlerrm<>'Selling price cannot be lower than payments already received' then raise; end if; end;
 update public.lm_orders set status='Delivered' where id=o.id;
 if (select delivered_date from public.lm_orders where id=o.id) is null then raise exception 'Delivery date not recorded'; end if;
 insert into public.lm_purchases(purchase_date,vendor,item,category,quantity,amount,order_id,status) values('2026-10-05','Test vendor','Fabric','Fabric',4,12000,o.id,'Unpaid');
 insert into public.lm_expenses(expense_date,description,category,amount,paid_by,order_id) values('2026-10-05','Test tailoring','Tailoring',3000,'Test staff',o.id);
 insert into public.lm_alterations(order_id,issue,received_date,status,additional_cost) values(o.id,'Test issue','2026-10-05','Received',500);
 insert into public.lm_salaries(staff_name,salary,frequency,period_start,period_end,deduction) values('Test staff',10000,'Monthly','2026-10-01','2026-10-31',1000) returning id into sid;
 insert into public.lm_salary_payments(salary_id,payment_date,amount,kind) values(sid,'2026-10-05',2000,'Advance');
 begin
  insert into public.lm_salary_payments(salary_id,payment_date,amount,kind) values(sid,'2026-10-05',8000,'Salary');
  raise exception 'Salary overpayment allowed';
 exception when raise_exception then if sqlerrm<>'Payment exceeds the remaining salary balance' then raise; end if; end;
 begin
  perform public.lm_create_order('{"reference":"__must_rollback__","order_date":"2026-10-05","due_date":"2026-10-15","product":"Test","quantity":1,"amount":100,"status":"New Order","advance_date":"2026-10-05"}'::jsonb,200,'{"name":"__rollback_client__"}'::jsonb);
  raise exception 'Invalid advance allowed';
 exception when raise_exception then if sqlerrm<>'Payment exceeds the remaining order balance' then raise; end if; end;
 if exists(select 1 from public.lm_customers where name='__rollback_client__') then raise exception 'Atomic create left partial client'; end if;
end $$;
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
set local role authenticated;
do $$ begin
 if exists(select 1 from public.lm_order_payments) or exists(select 1 from public.lm_salaries) then raise exception 'Nonstaff read allowed'; end if;
 begin
  perform public.lm_create_order('{"reference":"__unauthorized__","order_date":"2026-10-05","product":"Test","amount":1,"status":"New Order"}'::jsonb,0,'{"name":"__unauthorized_client__"}'::jsonb);
  raise exception 'Nonstaff RPC write allowed';
 exception when insufficient_privilege then null; end;
 begin
  insert into public.lm_purchases(purchase_date,vendor,item,category,quantity,amount,status) values('2026-10-05','Test','Test','Fabric',1,1,'Paid');
  raise exception 'Nonstaff write allowed';
 exception when insufficient_privilege then null; end;
end $$;
select 'Staff workflows, payment guards, atomic creation, and nonstaff denial passed' as result;
rollback;
