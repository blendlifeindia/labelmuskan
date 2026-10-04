begin;
create schema if not exists lm_private;
revoke all on schema lm_private from public;
grant usage on schema lm_private to authenticated;

create table public.lm_staff (
 user_id uuid primary key references auth.users(id) on delete cascade,
 created_at timestamptz not null default now()
);
alter table public.lm_staff enable row level security;
revoke all on public.lm_staff from authenticated;
grant select on public.lm_staff to authenticated;
revoke all on public.lm_staff from anon;
create policy staff_self_read on public.lm_staff for select to authenticated using (user_id=(select auth.uid()));

create function lm_private.is_staff() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.lm_staff where user_id=(select auth.uid()));
$$;
revoke all on function lm_private.is_staff() from public;
grant execute on function lm_private.is_staff() to authenticated;

create table public.lm_orders (
 id uuid primary key default gen_random_uuid(), created_at timestamptz not null default now(),
 reference text not null unique check(length(trim(reference))>0), customer_name text not null, product text not null,
 quantity numeric not null check(quantity>0), amount numeric not null default 0 check(amount>=0), paid numeric not null default 0 check(paid>=0 and paid<=amount),
 due_date date, status text not null default 'New' check(status in ('New','Confirmed','In production','Ready','Shipped','Delivered','Cancelled')), notes text
);
create table public.lm_production (
 id uuid primary key default gen_random_uuid(), created_at timestamptz not null default now(),
 reference text not null unique check(length(trim(reference))>0), order_reference text, product text not null,
 quantity numeric not null check(quantity>0), assigned_to text, due_date date,
 status text not null default 'Cutting' check(status in ('Cutting','Stitching','Finishing','Quality check','Complete')), notes text
);
create table public.lm_inventory (
 id uuid primary key default gen_random_uuid(), created_at timestamptz not null default now(),
 sku text not null unique check(length(trim(sku))>0), name text not null,
 category text not null check(category in ('Fabric','Trims','Finished goods','Packaging')),
 quantity numeric not null default 0 check(quantity>=0), unit text not null check(unit in ('Pieces','Metres','Sets','Kg')),
 reorder_level numeric not null default 0 check(reorder_level>=0), cost numeric not null default 0 check(cost>=0), notes text
);
create table public.lm_customers (
 id uuid primary key default gen_random_uuid(), created_at timestamptz not null default now(), name text not null check(length(trim(name))>0),
 phone text, email text, city text, address text, notes text
);
create table public.lm_expenses (
 id uuid primary key default gen_random_uuid(), created_at timestamptz not null default now(), description text not null,
 category text not null check(category in ('Materials','Labour','Shipping','Rent','Utilities','Marketing','Other')),
 amount numeric not null check(amount>=0), expense_date date not null, vendor text,
 status text not null check(status in ('Paid','Unpaid')), notes text
);
do $$ declare t text; begin
 foreach t in array array['lm_orders','lm_production','lm_inventory','lm_customers','lm_expenses'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from anon',t);
  execute format('revoke all on public.%I from authenticated',t);
  execute format('grant select, insert, update on public.%I to authenticated',t);
  execute format('create policy staff_select on public.%I for select to authenticated using ((select lm_private.is_staff()))',t);
  execute format('create policy staff_insert on public.%I for insert to authenticated with check ((select lm_private.is_staff()))',t);
  execute format('create policy staff_update on public.%I for update to authenticated using ((select lm_private.is_staff())) with check ((select lm_private.is_staff()))',t);
 end loop;
end $$;
create index on public.lm_orders(due_date);
create index on public.lm_expenses(expense_date);
create index on public.lm_orders(created_at desc);
create index on public.lm_production(created_at desc);
create index on public.lm_inventory(created_at desc);
create index on public.lm_customers(created_at desc);
create index on public.lm_expenses(created_at desc);
revoke execute on function public.rls_auto_enable() from public, anon, authenticated;
commit;
