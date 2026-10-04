begin;
alter table public.lm_customers add column instagram text, add column measurements text, add column preferences text;
alter table public.lm_orders add column customer_id uuid references public.lm_customers(id), add column order_date date not null default current_date, add column payment_due_date date, add column assigned_to text, add column delivered_date date;
update public.lm_orders set order_date=(created_at at time zone 'Asia/Kolkata')::date;
alter table public.lm_orders drop constraint lm_orders_status_check;
update public.lm_orders set status=case status when 'New' then 'New Order' when 'Confirmed' then 'Measurement Pending' when 'In production' then 'Stitching' when 'Shipped' then 'Ready' else status end;
alter table public.lm_orders alter column status set default 'New Order';
alter table public.lm_orders add constraint lm_orders_status_check check(status in ('New Order','Measurement Pending','Fabric Pending','Cutting','Stitching','Embroidery/Handwork','Trial Pending','Alteration','Ready','Delivered','Cancelled'));

alter table public.lm_expenses drop constraint lm_expenses_category_check;
update public.lm_expenses set category=case category when 'Materials' then 'Fabric' when 'Labour' then 'Tailoring' when 'Shipping' then 'Courier' when 'Utilities' then 'Electricity' when 'Marketing' then 'Marketing/PR' when 'Other' then 'Miscellaneous' else category end;
alter table public.lm_expenses add constraint lm_expenses_category_check check(category in ('Fabric','Tailoring','Embroidery','Dyer','Packaging','Courier','Staff','Rent','Electricity','Marketing/PR','Travel','Food/Hospitality','Repairs','Miscellaneous'));
alter table public.lm_expenses add column paid_by text, add column payment_mode text not null default 'UPI', add column order_id uuid references public.lm_orders(id);
alter table public.lm_expenses alter column status set default 'Paid';
alter table public.lm_inventory add column colour text, add column vendor text;

create table public.lm_purchases (
 id uuid primary key default gen_random_uuid(), created_at timestamptz not null default now(), purchase_date date not null,
 vendor text not null check(length(trim(vendor))>0), item text not null check(length(trim(item))>0),
 category text not null check(category in ('Fabric','Lining','Trims','Lace','Buttons','Zips','Embroidery material','Packaging','Accessories','Other')),
 quantity numeric not null check(quantity>0), amount numeric not null check(amount>=0), order_id uuid references public.lm_orders(id),
 status text not null check(status in ('Paid','Part paid','Unpaid')), notes text
);
create table public.lm_order_payments (
 id uuid primary key default gen_random_uuid(), created_at timestamptz not null default now(), order_id uuid not null references public.lm_orders(id),
 payment_date date not null, amount numeric not null check(amount>0), kind text not null default 'Payment' check(kind in ('Advance','Payment')),
 payment_mode text not null default 'UPI', voided boolean not null default false, notes text
);
insert into public.lm_order_payments(order_id,payment_date,amount,kind,notes) select id,order_date,paid,'Advance','Opening balance migrated from the original dashboard' from public.lm_orders where paid>0;
create table public.lm_salaries (
 id uuid primary key default gen_random_uuid(), created_at timestamptz not null default now(), staff_name text not null check(length(trim(staff_name))>0),
 salary numeric not null check(salary>=0), frequency text not null check(frequency in ('Weekly','Monthly')),
 period_start date not null, period_end date not null check(period_end>=period_start), deduction numeric not null default 0 check(deduction>=0 and deduction<=salary), notes text,
 unique(staff_name,period_start,period_end)
);
create table public.lm_salary_payments (
 id uuid primary key default gen_random_uuid(), created_at timestamptz not null default now(), salary_id uuid not null references public.lm_salaries(id),
 payment_date date not null, amount numeric not null check(amount>0), kind text not null check(kind in ('Salary','Advance')),
 payment_mode text not null default 'UPI', voided boolean not null default false, notes text
);
create table public.lm_alterations (
 id uuid primary key default gen_random_uuid(), created_at timestamptz not null default now(), order_id uuid not null references public.lm_orders(id),
 issue text not null check(length(trim(issue))>0), received_date date not null, assigned_to text, expected_date date,
 status text not null check(status in ('Received','In progress','Ready','Returned','Cancelled')), additional_cost numeric not null default 0 check(additional_cost>=0), notes text
);
do $$ declare t text; begin
 foreach t in array array['lm_purchases','lm_order_payments','lm_salaries','lm_salary_payments','lm_alterations'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from public, anon, authenticated',t);
  execute format('grant select, insert, update on public.%I to authenticated',t);
  execute format('create policy staff_select on public.%I for select to authenticated using ((select lm_private.is_staff()))',t);
  execute format('create policy staff_insert on public.%I for insert to authenticated with check ((select lm_private.is_staff()))',t);
  execute format('create policy staff_update on public.%I for update to authenticated using ((select lm_private.is_staff())) with check ((select lm_private.is_staff()))',t);
 end loop;
end $$;
revoke update on public.lm_order_payments, public.lm_salary_payments from authenticated;
grant update(voided,notes) on public.lm_order_payments, public.lm_salary_payments to authenticated;

create function lm_private.validate_order_payment() returns trigger language plpgsql security invoker set search_path='' as $$
declare price numeric; received numeric; stage text;
begin
 select amount,status into price,stage from public.lm_orders where id=new.order_id for update;
 if not found then raise exception 'Order is unavailable'; end if;
 if new.voided then return new; end if;
 if stage='Cancelled' then raise exception 'Cannot collect a payment for a cancelled order'; end if;
 select coalesce(sum(amount),0) into received from public.lm_order_payments where order_id=new.order_id and not voided and id<>new.id;
 if received+new.amount>price then raise exception 'Payment exceeds the remaining order balance'; end if;
 return new;
end $$;
create trigger validate_order_payment before insert or update on public.lm_order_payments for each row execute function lm_private.validate_order_payment();
create function lm_private.validate_salary_payment() returns trigger language plpgsql security invoker set search_path='' as $$
declare owed numeric; paid numeric;
begin
 select salary-deduction into owed from public.lm_salaries where id=new.salary_id for update;
 if not found then raise exception 'Salary period is unavailable'; end if;
 if new.voided then return new; end if;
 select coalesce(sum(amount),0) into paid from public.lm_salary_payments where salary_id=new.salary_id and not voided and id<>new.id;
 if paid+new.amount>owed then raise exception 'Payment exceeds the remaining salary balance'; end if;
 return new;
end $$;
create trigger validate_salary_payment before insert or update on public.lm_salary_payments for each row execute function lm_private.validate_salary_payment();
create function lm_private.validate_order_value() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if new.amount<(select coalesce(sum(amount),0) from public.lm_order_payments where order_id=new.id and not voided) then raise exception 'Selling price cannot be lower than payments already received'; end if;
 if new.status='Delivered' and old.status<>'Delivered' then new.delivered_date=coalesce(new.delivered_date,(now() at time zone 'Asia/Kolkata')::date); end if;
 if new.status<>'Delivered' then new.delivered_date=null; end if;
 return new;
end $$;
create trigger validate_order_value before update on public.lm_orders for each row execute function lm_private.validate_order_value();
create function lm_private.validate_salary_value() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if new.salary-new.deduction<(select coalesce(sum(amount),0) from public.lm_salary_payments where salary_id=new.id and not voided) then raise exception 'Salary after deduction cannot be lower than payments already made'; end if;
 return new;
end $$;
create trigger validate_salary_value before update on public.lm_salaries for each row execute function lm_private.validate_salary_value();

create function public.lm_create_order(p_order jsonb,p_advance numeric default 0,p_new_client jsonb default null) returns public.lm_orders language plpgsql security invoker set search_path='' as $$
declare cid uuid; client_name text; result public.lm_orders;
begin
 if p_new_client is not null then
  insert into public.lm_customers(name,phone,instagram,city) values(p_new_client->>'name',p_new_client->>'phone',p_new_client->>'instagram',p_new_client->>'city') returning id,name into cid,client_name;
 else
  cid=(p_order->>'customer_id')::uuid;
  select name into client_name from public.lm_customers where id=cid;
 end if;
 if client_name is null then raise exception 'Choose a client'; end if;
 if p_advance<0 then raise exception 'Advance cannot be negative'; end if;
 insert into public.lm_orders(reference,customer_id,customer_name,order_date,due_date,payment_due_date,product,quantity,amount,status,assigned_to,notes,delivered_date)
 values(p_order->>'reference',cid,client_name,(p_order->>'order_date')::date,(p_order->>'due_date')::date,(p_order->>'payment_due_date')::date,p_order->>'product',coalesce((p_order->>'quantity')::numeric,1),(p_order->>'amount')::numeric,p_order->>'status',p_order->>'assigned_to',p_order->>'notes',case when p_order->>'status'='Delivered' then (p_order->>'order_date')::date else null end)
 returning * into result;
 if p_advance>0 then insert into public.lm_order_payments(order_id,payment_date,amount,kind,payment_mode) values(result.id,(p_order->>'advance_date')::date,p_advance,'Advance',coalesce(p_order->>'payment_mode','UPI')); end if;
 return result;
end $$;
revoke all on function public.lm_create_order(jsonb,numeric,jsonb) from public,anon;
grant execute on function public.lm_create_order(jsonb,numeric,jsonb) to authenticated;

create index on public.lm_orders(customer_id);
create index on public.lm_orders(order_date);
create index on public.lm_order_payments(order_id);
create index on public.lm_order_payments(payment_date);
create index on public.lm_salary_payments(salary_id);
create index on public.lm_salary_payments(payment_date);
create index on public.lm_purchases(order_id);
create index on public.lm_purchases(purchase_date);
create index on public.lm_alterations(order_id);
create index on public.lm_expenses(order_id);
revoke execute on function lm_private.validate_order_payment(),lm_private.validate_salary_payment(),lm_private.validate_order_value(),lm_private.validate_salary_value() from public,anon,authenticated;
commit;
