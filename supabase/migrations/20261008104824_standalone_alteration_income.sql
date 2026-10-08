create table public.lm_walkin_alterations(
 id uuid primary key default gen_random_uuid(),description text not null check(length(trim(description)) between 1 and 300),
 client_name text,charge numeric(12,2) not null check(charge>0),entry_date date not null,voided boolean not null default false,
 created_at timestamptz not null default now(),created_by uuid not null default auth.uid());
create table public.lm_walkin_payments(
 id uuid primary key default gen_random_uuid(),alteration_id uuid not null references public.lm_walkin_alterations(id),
 amount numeric(12,2) not null check(amount>0),payment_date date not null,payment_mode text,
 voided boolean not null default false,created_at timestamptz not null default now(),created_by uuid not null default auth.uid(),
 check(payment_mode is null or payment_mode in ('Cash','UPI','Bank transfer','Card')));
create index on public.lm_walkin_payments(alteration_id);
create index on public.lm_walkin_payments(payment_date) where not voided;
alter table public.lm_walkin_alterations enable row level security;
alter table public.lm_walkin_payments enable row level security;
create policy walkin_access on public.lm_walkin_alterations for all to authenticated using(lm_private.is_staff() and lm_private.can('payments')) with check(lm_private.is_staff() and lm_private.can('payments'));
create policy walkin_payment_access on public.lm_walkin_payments for all to authenticated using(lm_private.is_staff() and lm_private.can('payments')) with check(lm_private.is_staff() and lm_private.can('payments'));
revoke all on public.lm_walkin_alterations,public.lm_walkin_payments from anon,authenticated;
grant select,insert,update on public.lm_walkin_alterations,public.lm_walkin_payments to authenticated;
create function public.lm_walkin_list() returns jsonb language sql stable security invoker set search_path='' as $$
 select coalesce(jsonb_agg(to_jsonb(a)||jsonb_build_object('paid',coalesce((select sum(p.amount) from public.lm_walkin_payments p where p.alteration_id=a.id and not p.voided),0),'payments',coalesce((select jsonb_agg(to_jsonb(p) order by p.payment_date desc,p.created_at desc) from public.lm_walkin_payments p where p.alteration_id=a.id),'[]'::jsonb)) order by a.entry_date desc,a.created_at desc),'[]'::jsonb) from public.lm_walkin_alterations a;
$$;
create function public.lm_save_walkin(p_body jsonb,p_id uuid default null) returns uuid language plpgsql security invoker set search_path='' as $$
declare saved uuid;already_paid numeric;initial_paid numeric:=coalesce((p_body->>'paid')::numeric,0);begin
 if auth.uid() is null or not lm_private.is_staff() or not lm_private.can('payments') then raise insufficient_privilege using message='Payment access required';end if;
 if p_id is null then
 if initial_paid<0 or initial_paid>(p_body->>'charge')::numeric then raise exception 'Paid amount must be within the charge';end if;
 insert into public.lm_walkin_alterations(id,description,client_name,charge,entry_date) values(coalesce((p_body->>'id')::uuid,gen_random_uuid()),trim(p_body->>'description'),nullif(trim(p_body->>'client_name'),''),(p_body->>'charge')::numeric,(p_body->>'entry_date')::date) returning id into saved;
 if initial_paid>0 then insert into public.lm_walkin_payments(alteration_id,amount,payment_date,payment_mode) values(saved,initial_paid,(p_body->>'entry_date')::date,nullif(p_body->>'payment_mode',''));end if;
 else
 perform 1 from public.lm_walkin_alterations where id=p_id and not voided for update;
 if not found then raise exception 'Alteration unavailable';end if;
 select coalesce(sum(amount),0) into already_paid from public.lm_walkin_payments where alteration_id=p_id and not voided;
 if (p_body->>'charge')::numeric<already_paid then raise exception 'Charge cannot be less than recorded payments';end if;
 update public.lm_walkin_alterations set description=trim(p_body->>'description'),client_name=nullif(trim(p_body->>'client_name'),''),charge=(p_body->>'charge')::numeric,entry_date=(p_body->>'entry_date')::date where id=p_id;
 saved:=p_id;
 end if;return saved;end $$;
create function public.lm_pay_walkin(p_id uuid,p_amount numeric,p_date date,p_mode text default null,p_payment_id uuid default gen_random_uuid()) returns uuid language plpgsql security invoker set search_path='' as $$
declare charge numeric;paid numeric;begin
 if auth.uid() is null or not lm_private.is_staff() or not lm_private.can('payments') then raise insufficient_privilege using message='Payment access required';end if;
 select a.charge into charge from public.lm_walkin_alterations a where id=p_id and not voided for update;
 if not found then raise exception 'Alteration unavailable';end if;
 select coalesce(sum(amount),0) into paid from public.lm_walkin_payments where alteration_id=p_id and not voided;
 if p_amount is null or p_amount<=0 or p_amount>charge-paid then raise exception 'Enter an amount within the remaining balance';end if;
 insert into public.lm_walkin_payments(id,alteration_id,amount,payment_date,payment_mode) values(p_payment_id,p_id,p_amount,p_date,nullif(p_mode,''));
 return p_payment_id;end $$;
create function public.lm_void_walkin(p_id uuid,p_payment boolean default false,p_voided boolean default true) returns boolean language plpgsql security invoker set search_path='' as $$
begin
 if auth.uid() is null or not lm_private.is_staff() or not lm_private.can('payments') then raise insufficient_privilege using message='Payment access required';end if;
 if p_payment then update public.lm_walkin_payments set voided=p_voided where id=p_id;
 else update public.lm_walkin_alterations set voided=p_voided where id=p_id;end if;
 if not found then raise exception 'Entry unavailable';end if;return true;end $$;
revoke all on function public.lm_walkin_list(),public.lm_save_walkin(jsonb,uuid),public.lm_pay_walkin(uuid,numeric,date,text,uuid),public.lm_void_walkin(uuid,boolean,boolean) from public,anon;
grant execute on function public.lm_walkin_list(),public.lm_save_walkin(jsonb,uuid),public.lm_pay_walkin(uuid,numeric,date,text,uuid),public.lm_void_walkin(uuid,boolean,boolean) to authenticated;
do $$ declare definition text;signature text;date_filter text;needle text;addition text;begin
 foreach signature in array array['lm_private.month_money(text)','lm_private.range_money(date,date)'] loop
 definition:=pg_get_functiondef(signature::regprocedure);
 date_filter:=case when signature like '%month_money%' then 'firstday and lastday' else 'p_from and p_to' end;
 needle:='select coalesce(sum(amount),0) into collected from public.lm_order_payments where not voided and payment_date between '||date_filter||';';
 addition:=needle||' collected:=collected+coalesce((select sum(p.amount) from public.lm_walkin_payments p join public.lm_walkin_alterations a on a.id=p.alteration_id where not p.voided and not a.voided and p.payment_date between '||date_filter||'),0);';
 if position(needle in definition)=0 then raise exception 'Summary integration missing';end if;
 execute replace(definition,needle,addition);
 end loop;
end $$;
