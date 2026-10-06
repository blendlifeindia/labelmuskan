-- Synthetic entries roll back; only the approved Supabase project.
begin;
insert into auth.users(id,email,email_confirmed_at) values('50000000-0000-4000-8000-000000000001','sheet-production@example.invalid',now());
insert into public.lm_staff(user_id,role,permissions) values('50000000-0000-4000-8000-000000000001','production',array['orders']);
set local role authenticated;
select set_config('request.jwt.claim.sub','620ff01b-a3bb-4c91-9242-43a8ce4a49e4',true);
do $$ declare eid uuid;pid uuid;sid uuid;payid uuid;base numeric;v numeric;begin
 base=(public.lm_month_money('2026-10')->>'total_out')::numeric;
 eid=(public.lm_save_record('expenses','{"expense_date":"2026-10-06","description":"Sheet rollback expense","category":"Courier","amount":100,"status":"Pending","paid_by":"Owner","payment_mode":"UPI"}',null)->>'id')::uuid;
 if (public.lm_month_money('2026-10')->>'total_out')::numeric<>base then raise exception 'Pending expense counted';end if;
 perform public.lm_save_record('expenses','{"status":"Paid"}',eid);
 if (public.lm_month_money('2026-10')->>'total_out')::numeric<>base+100 then raise exception 'Paid expense missing';end if;
 perform public.lm_set_expense_void('expenses',eid,true);
 if (public.lm_month_money('2026-10')->>'total_out')::numeric<>base then raise exception 'Voided expense counted';end if;
 perform public.lm_set_expense_void('expenses',eid,false);
 pid=(public.lm_save_record('purchases','{"purchase_date":"2026-10-06","item":"Sheet rollback purchase","category":"Fabric","vendor":"Test","quantity":2,"amount":500,"status":"Paid"}',null)->>'id')::uuid;
 perform public.lm_set_expense_void('purchases',pid,true);
 if (public.lm_month_money('2026-10')->>'total_out')::numeric<>base+100 then raise exception 'Voided purchase counted';end if;
 perform public.lm_set_expense_void('purchases',pid,false);
 sid=(public.lm_save_record('salary_profiles','{"staff_name":"Sheet rollback staff","job_role":"Tailor","amount":1000,"frequency":"Weekly","payment_day":"Saturday"}',null)->>'id')::uuid;
 payid=(public.lm_save_record('salary_payouts',jsonb_build_object('profile_id',sid,'payment_date','2026-10-06','amount',1000,'kind','Salary','payment_mode','Cash'),null)->>'id')::uuid;
 perform public.lm_save_record('salary_payouts','{"amount":900,"payment_date":"2026-09-26","payment_mode":"UPI"}',payid);
 if (public.lm_month_money('2026-10')->>'total_out')::numeric<>base+600 then raise exception 'Salary edit did not move actual dated payment';end if;
 perform public.lm_set_expense_void('salary_payouts',payid,true);
 perform public.lm_set_expense_void('salary_payouts',payid,false);
 begin perform public.lm_save_record('salary_payouts',jsonb_build_object('profile_id',sid),payid);raise exception 'Payout payee changed';exception when insufficient_privilege then null;end;
 perform set_config('test.sheet_id',eid::text,true);
end $$;
select set_config('request.jwt.claim.sub','50000000-0000-4000-8000-000000000001',true);
do $$ begin
 begin perform public.lm_set_expense_void('expenses',current_setting('test.sheet_id')::uuid,true);raise exception 'Production voided expenses';exception when insufficient_privilege then null;end;
 begin perform public.lm_set_expense_void('orders',current_setting('test.sheet_id')::uuid,true);raise exception 'Wrong record type accepted';exception when insufficient_privilege then null;end;
 if has_function_privilege('anon','public.lm_set_expense_void(text,uuid,boolean)','execute') then raise exception 'Anonymous expense mutation';end if;
end $$;
select 'Pending/paid totals, void/restore, salary edits and expense permissions passed' result;
rollback;
