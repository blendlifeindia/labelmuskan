-- Approved project xybqwszhkbiucgextwog. Internal photos are not publicly hosted.
create table public.lm_influencer_marketing (
 id uuid primary key default gen_random_uuid(),
 created_at timestamptz not null default now(),
 created_by uuid not null default auth.uid() references auth.users(id),
 influencer_name text not null check(length(trim(influencer_name)) between 1 and 200),
 outfit_name text not null check(length(trim(outfit_name)) between 1 and 300),
 agency_name text check(length(agency_name)<=200),
 sent_through text check(length(sent_through)<=200),
 sent_date date,
 collaboration text not null check(collaboration in ('Barter','Sourcing')),
 status text not null check(status in ('Planned','Sent','Received','Posted','Returned','Cancelled')),
 image_data text check(image_data is null or (length(image_data)<=300000 and image_data ~ '^data:image/jpeg;base64,[A-Za-z0-9+/]+={0,2}$'))
);
alter table public.lm_influencer_marketing enable row level security;
revoke all on public.lm_influencer_marketing from public,anon,authenticated;
create policy marketing_access on public.lm_influencer_marketing to authenticated
 using ((select lm_private.is_staff()) and (select lm_private.can('marketing')))
 with check ((select lm_private.is_staff()) and (select lm_private.can('marketing')));
create index lm_marketing_sent_date on public.lm_influencer_marketing(sent_date desc,created_at desc);

create function lm_private.workspace_marketing() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;begin
 result:=lm_private.workspace();
 if auth.uid() is not null and lm_private.is_staff() and lm_private.can('marketing') then
  result:=result||jsonb_build_object('influencer_marketing',(select coalesce(jsonb_agg(to_jsonb(m) order by m.sent_date desc nulls last,m.created_at desc),'[]'::jsonb) from public.lm_influencer_marketing m));
 end if;
 return result;
end $$;
create or replace function public.lm_workspace() returns jsonb language sql security invoker set search_path='' as $$select lm_private.workspace_marketing();$$;

create function lm_private.save_marketing(p_body jsonb,p_id uuid default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare result uuid;begin
 if auth.uid() is null or not lm_private.is_staff() or not lm_private.can('marketing') then raise insufficient_privilege using message='Influencer Marketing access required';end if;
 if jsonb_typeof(p_body) is distinct from 'object' then raise exception 'Provide collaboration details';end if;
 if p_id is null then
  insert into public.lm_influencer_marketing(influencer_name,outfit_name,agency_name,sent_through,sent_date,collaboration,status,image_data)
  values(trim(p_body->>'influencer_name'),trim(p_body->>'outfit_name'),nullif(trim(p_body->>'agency_name'),''),nullif(trim(p_body->>'sent_through'),''),nullif(p_body->>'sent_date','')::date,p_body->>'collaboration',p_body->>'status',nullif(p_body->>'image_data','')) returning id into result;
 else
  update public.lm_influencer_marketing set influencer_name=trim(p_body->>'influencer_name'),outfit_name=trim(p_body->>'outfit_name'),agency_name=nullif(trim(p_body->>'agency_name'),''),sent_through=nullif(trim(p_body->>'sent_through'),''),sent_date=nullif(p_body->>'sent_date','')::date,collaboration=p_body->>'collaboration',status=p_body->>'status',image_data=nullif(p_body->>'image_data','') where id=p_id returning id into result;
  if result is null then raise exception 'Collaboration is unavailable';end if;
 end if;
 return jsonb_build_object('saved',true,'id',result);
end $$;
create function public.lm_save_marketing(p_body jsonb,p_id uuid default null) returns jsonb language sql security invoker set search_path='' as $$select lm_private.save_marketing(p_body,p_id);$$;
revoke all on function lm_private.workspace_marketing(),lm_private.save_marketing(jsonb,uuid),public.lm_save_marketing(jsonb,uuid) from public,anon;
grant execute on function lm_private.workspace_marketing(),lm_private.save_marketing(jsonb,uuid),public.lm_save_marketing(jsonb,uuid) to authenticated;
CREATE OR REPLACE FUNCTION lm_private.invoice(p_order_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare o public.lm_orders;begin
 if auth.uid() is null or not lm_private.is_staff() or not lm_private.can('payments') or not lm_private.can('clients') then raise insufficient_privilege using message='Client and payment access required to generate invoices';end if;
 select * into o from public.lm_orders where id=p_order_id;
 if not found then raise exception 'Order is unavailable';end if;
 if o.status='Cancelled' then raise exception 'Cancelled orders cannot be invoiced';end if;
 return jsonb_build_object('order',jsonb_build_object('id',o.id,'reference',o.reference,'invoice_number',o.invoice_number,'invoice_date',o.invoice_date,'payment_due_date',o.payment_due_date,'due_date',o.due_date,'fitting_date',o.fitting_date,'amount',o.amount,'payment_mode',o.payment_mode),'client',(select jsonb_build_object('name',c.name,'phone',c.phone) from public.lm_customers c where c.id=o.customer_id),'items',(select coalesce(jsonb_agg(jsonb_build_object('id',i.id,'name',i.name,'quantity',i.quantity,'price',i.price) order by i.position),'[]') from public.lm_order_items i where i.order_id=o.id),'payments',(select coalesce(jsonb_agg(jsonb_build_object('amount',p.amount,'payment_date',p.payment_date,'kind',p.kind,'payment_mode',p.payment_mode)),'[]') from public.lm_order_payments p where p.order_id=o.id and not p.voided));
end $function$;

CREATE OR REPLACE FUNCTION lm_private.manage_member(p_email text, p_role text, p_permissions text[], p_name text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid;begin
 if not lm_private.can('owner') then raise insufficient_privilege using message='Only Muskan can manage team access';end if;
 if p_role not in ('production','team','accounts') or not p_permissions<@array['home','orders','clients','studio','production','tasks','calendar','payments','expenses','purchases','salaries','marketing'] then raise exception 'Choose a permitted team role and access';end if;
 select id into uid from auth.users where lower(email)=lower(trim(p_email)) and email_confirmed_at is not null;
 if uid is null then raise exception 'Create a confirmed login for this email in Supabase Authentication first';end if;
 if exists(select 1 from public.lm_staff where user_id=uid and role='owner') then raise exception 'The owner account cannot be changed';end if;
 insert into public.lm_staff(user_id,role,permissions,display_name) values(uid,p_role,p_permissions,p_name) on conflict(user_id) do update set role=excluded.role,permissions=excluded.permissions,display_name=excluded.display_name;
 return jsonb_build_object('saved',true);
end $function$;
