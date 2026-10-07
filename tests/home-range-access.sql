begin;
select set_config('request.jwt.claim.sub',(select user_id::text from public.lm_staff where role='owner' limit 1),true);
set local role authenticated;
do $$declare r jsonb;m jsonb;begin
 r=public.lm_range_money('2026-10-01','2026-10-31');m=public.lm_month_money('2026-10');
 if r->'sales'<>m->'sales' or r->'collected'<>m->'collected' or r->'outstanding'<>m->'outstanding' then raise exception 'Monthly parity failed';end if;
 begin perform public.lm_range_money('2026-10-08','2026-10-07');raise exception 'Invalid range was accepted';exception when others then if sqlerrm='Invalid range was accepted' then raise;end if;end;
 if has_function_privilege('anon','public.lm_range_money(date,date)','execute') then raise exception 'Anonymous access granted';end if;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000099',true);
do $$begin begin perform public.lm_range_money('2026-10-01','2026-10-31');raise exception 'Unapproved user gained access';exception when insufficient_privilege then null;end;end$$;
rollback;
