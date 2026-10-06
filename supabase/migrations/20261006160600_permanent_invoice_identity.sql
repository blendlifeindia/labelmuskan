begin;
create sequence public.lm_invoice_number_seq;
revoke all on sequence public.lm_invoice_number_seq from public,anon,authenticated;
alter table public.lm_orders add column invoice_number text not null default ('LM-'||to_char(now() at time zone 'Asia/Kolkata','YYYY')||'-'||lpad(nextval('public.lm_invoice_number_seq')::text,6,'0'));
alter table public.lm_orders add constraint lm_orders_invoice_number_key unique(invoice_number);
alter table public.lm_orders add column invoice_date date;
update public.lm_orders set invoice_date=coalesce(order_date,(created_at at time zone 'Asia/Kolkata')::date);
alter table public.lm_orders alter column invoice_date set default ((now() at time zone 'Asia/Kolkata')::date);
alter table public.lm_orders alter column invoice_date set not null;
create function lm_private.invoice(p_order_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare o public.lm_orders;begin
 if auth.uid() is null or not lm_private.is_staff() or not lm_private.can('payments') or not lm_private.can('clients') then raise insufficient_privilege using message='Client and payment access required to generate invoices';end if;
 select * into o from public.lm_orders where id=p_order_id;
 if not found then raise exception 'Order is unavailable';end if;
 if o.status='Cancelled' then raise exception 'Cancelled orders cannot be invoiced';end if;
 return jsonb_build_object('order',to_jsonb(o)-'delivery_previous_stages','client',(select jsonb_build_object('name',c.name,'phone',c.phone,'address',c.address) from public.lm_customers c where c.id=o.customer_id),'items',(select coalesce(jsonb_agg(jsonb_build_object('id',i.id,'name',i.name,'fabric',i.fabric,'quantity',i.quantity,'price',i.price) order by i.position),'[]') from public.lm_order_items i where i.order_id=o.id),'payments',(select coalesce(jsonb_agg(jsonb_build_object('amount',p.amount,'payment_date',p.payment_date,'kind',p.kind)),'[]') from public.lm_order_payments p where p.order_id=o.id and not p.voided));
end $$;
create function public.lm_invoice(p_order_id uuid) returns jsonb language sql stable security invoker set search_path='' as $$select lm_private.invoice(p_order_id)$$;
revoke all on function lm_private.invoice(uuid),public.lm_invoice(uuid) from public,anon,authenticated;
grant execute on function lm_private.invoice(uuid),public.lm_invoice(uuid) to authenticated;
commit;
