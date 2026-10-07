lock table public.lm_orders in access exclusive mode;
create table lm_private.invoice_renumber_backup_1001 as select id as order_id,invoice_number as old_invoice_number,(invoice_number::bigint+1000)::text as new_invoice_number,now() as changed_at from public.lm_orders;
revoke all on lm_private.invoice_renumber_backup_1001 from public,anon,authenticated;
do $$ begin
 if exists(select 1 from public.lm_orders where invoice_number !~ '^[0-9]+$' or invoice_number::bigint>=1000) then raise exception 'Unexpected invoice format; aborting renumber'; end if;
end $$;
update public.lm_orders o set invoice_number=m.new_invoice_number from lm_private.invoice_renumber_backup_1001 m where m.order_id=o.id;
alter table public.lm_orders alter column invoice_number set default (nextval('public.lm_invoice_number_seq'::regclass)::text);
do $$ declare next_number bigint; begin select greatest(1001,coalesce(max(invoice_number::bigint)+1,1001)) into next_number from public.lm_orders; execute format('alter sequence public.lm_invoice_number_seq restart with %s',next_number); end $$;
