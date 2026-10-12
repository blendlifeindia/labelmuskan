create table public.lm_fabrics(id uuid primary key default gen_random_uuid(),name text not null check(length(trim(name)) between 1 and 150),colour text,vendor text,reorder_metres numeric(12,2) not null default 0 check(reorder_metres>=0),next_purchase_date date,notes text,voided boolean not null default false,created_at timestamptz not null default now());
create table public.lm_fabric_moves(id uuid primary key default gen_random_uuid(),fabric_id uuid not null references public.lm_fabrics(id),kind text not null check(kind in ('Purchased','Used')),metres numeric(12,2) not null check(metres>0),move_date date not null,notes text,voided boolean not null default false,created_at timestamptz not null default now(),created_by uuid not null default auth.uid());
create index on public.lm_fabric_moves(fabric_id) where not voided;
alter table public.lm_fabrics enable row level security;alter table public.lm_fabric_moves enable row level security;
create policy fabric_access on public.lm_fabrics for all to authenticated using(lm_private.is_staff() and lm_private.can('purchases')) with check(lm_private.is_staff() and lm_private.can('purchases'));
create policy fabric_move_access on public.lm_fabric_moves for all to authenticated using(lm_private.is_staff() and lm_private.can('purchases')) with check(lm_private.is_staff() and lm_private.can('purchases'));
revoke all on public.lm_fabrics,public.lm_fabric_moves from anon,authenticated;
grant select,insert,update on public.lm_fabrics,public.lm_fabric_moves to authenticated;
create function public.lm_fabric_list() returns jsonb language sql stable security invoker set search_path='' as $$
select coalesce(jsonb_agg(to_jsonb(f)||jsonb_build_object('moves',coalesce((select jsonb_agg(to_jsonb(m) order by move_date desc,created_at desc) from public.lm_fabric_moves m where fabric_id=f.id),'[]'::jsonb)) order by f.name),'[]'::jsonb) from public.lm_fabrics f;$$;
create function public.lm_save_fabric(p_body jsonb,p_id uuid default null) returns uuid language plpgsql security invoker set search_path='' as $$
declare saved uuid;begin
if auth.uid() is null or not lm_private.is_staff() or not lm_private.can('purchases') then raise insufficient_privilege using message='Fabric access requires purchase permission';end if;
if p_id is null then insert into public.lm_fabrics(id,name,colour,vendor,reorder_metres,next_purchase_date,notes) values(coalesce((p_body->>'id')::uuid,gen_random_uuid()),trim(p_body->>'name'),nullif(trim(p_body->>'colour'),''),nullif(trim(p_body->>'vendor'),''),coalesce((p_body->>'reorder_metres')::numeric,0),nullif(p_body->>'next_purchase_date','')::date,nullif(trim(p_body->>'notes'),'')) returning id into saved;
else update public.lm_fabrics set name=trim(p_body->>'name'),colour=nullif(trim(p_body->>'colour'),''),vendor=nullif(trim(p_body->>'vendor'),''),reorder_metres=coalesce((p_body->>'reorder_metres')::numeric,0),next_purchase_date=nullif(p_body->>'next_purchase_date','')::date,notes=nullif(trim(p_body->>'notes'),'') where id=p_id and not voided returning id into saved;if saved is null then raise exception 'Fabric unavailable';end if;end if;return saved;end $$;
create function public.lm_fabric_move(p_fabric_id uuid,p_kind text,p_metres numeric,p_date date,p_notes text default null,p_id uuid default gen_random_uuid()) returns uuid language plpgsql security invoker set search_path='' as $$
declare remaining numeric;begin
if auth.uid() is null or not lm_private.is_staff() or not lm_private.can('purchases') then raise insufficient_privilege using message='Fabric access requires purchase permission';end if;
perform 1 from public.lm_fabrics where id=p_fabric_id and not voided for update;if not found then raise exception 'Fabric unavailable';end if;
select coalesce(sum(case when kind='Purchased' then metres else -metres end),0) into remaining from public.lm_fabric_moves where fabric_id=p_fabric_id and not voided;
if p_kind='Used' and p_metres>remaining then raise exception 'Usage exceeds available metres';end if;
insert into public.lm_fabric_moves(id,fabric_id,kind,metres,move_date,notes) values(p_id,p_fabric_id,p_kind,p_metres,p_date,nullif(trim(p_notes),''));return p_id;end $$;
create function public.lm_void_fabric(p_id uuid,p_move boolean default false,p_voided boolean default true) returns boolean language plpgsql security invoker set search_path='' as $$
declare f uuid;remaining numeric;begin
if auth.uid() is null or not lm_private.is_staff() or not lm_private.can('purchases') then raise insufficient_privilege using message='Fabric access requires purchase permission';end if;
if p_move then
select fabric_id into f from public.lm_fabric_moves where id=p_id;if f is null then raise exception 'Entry unavailable';end if;
perform 1 from public.lm_fabrics where id=f for update;
select coalesce(sum(case when kind='Purchased' then metres else -metres end),0) into remaining from public.lm_fabric_moves where fabric_id=f and case when id=p_id then not p_voided else not voided end;
if remaining<0 then raise exception 'This change would make stock negative. Correct usage first';end if;
update public.lm_fabric_moves set voided=p_voided where id=p_id;
else update public.lm_fabrics set voided=p_voided where id=p_id;end if;if not found then raise exception 'Entry unavailable';end if;return true;end $$;
revoke all on function public.lm_fabric_list(),public.lm_save_fabric(jsonb,uuid),public.lm_fabric_move(uuid,text,numeric,date,text,uuid),public.lm_void_fabric(uuid,boolean,boolean) from public,anon;
grant execute on function public.lm_fabric_list(),public.lm_save_fabric(jsonb,uuid),public.lm_fabric_move(uuid,text,numeric,date,text,uuid),public.lm_void_fabric(uuid,boolean,boolean) to authenticated;
