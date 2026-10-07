lock table public.lm_orders in access exclusive mode;
do $$ begin if exists(select 1 from public.lm_orders where reference !~ '^[0-9]+$') then raise exception 'Unexpected order number format'; end if; end $$;
create table lm_private.order_reference_backup_lm as select id as order_id,reference as old_reference,'LM-'||lpad((reference::bigint)::text,greatest(3,length((reference::bigint)::text)),'0') as new_reference,now() as changed_at from public.lm_orders;
revoke all on lm_private.order_reference_backup_lm from public,anon,authenticated;
update public.lm_orders o set reference=m.new_reference from lm_private.order_reference_backup_lm m where o.id=m.order_id;
