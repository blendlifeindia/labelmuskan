lock table public.lm_orders in access exclusive mode;
create sequence public.lm_order_number_seq;
revoke all on sequence public.lm_order_number_seq from public,anon,authenticated;
do $$ declare last_number bigint;begin
select coalesce(max(number),0) into last_number from (
select substring(reference from '^LM-([0-9]+)$')::bigint number from public.lm_orders
union all select substring(r->>'reference' from '^LM-([0-9]+)$')::bigint from lm_private.deleted_entries d cross join lateral jsonb_array_elements(coalesce(d.records->'orders','[]'::jsonb)) r where restored_at is null
) numbers;
execute format('alter sequence public.lm_order_number_seq restart with %s',last_number+1);
end $$;
create function lm_private.next_order_number() returns text language sql volatile security invoker set search_path='' as $$
select 'LM-'||lpad(value::text,greatest(3,length(value::text)),'0') from (select nextval('public.lm_order_number_seq'::regclass) value) x;
$$;
revoke all on function lm_private.next_order_number() from public,anon,authenticated;
alter table public.lm_orders alter column reference set default lm_private.next_order_number();
do $$ declare definition text;needle text:='if p_id is null then oid=coalesce';begin
definition:=pg_get_functiondef('lm_private.save_order(jsonb,jsonb,uuid,numeric)'::regprocedure);
if position(needle in definition)=0 then raise exception 'Order creation integration missing';end if;
definition:=replace(definition,needle,'if p_id is null then p_order:=jsonb_set(p_order,''{reference}'',to_jsonb(lm_private.next_order_number()));oid=coalesce');
execute definition;
end $$;
