-- Same Home permission as monthly totals; arbitrary periods never expose individual records.
create function lm_private.range_money(p_from date,p_to date) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare sales numeric;collected numeric;outstanding numeric;
begin
 if auth.uid() is null or not lm_private.can('home') then raise insufficient_privilege using message='Business totals require explicit owner permission';end if;
 if p_from is null or p_to is null or p_from>p_to then raise exception 'Choose a valid start and end date';end if;
 select coalesce(sum(amount),0) into sales from public.lm_orders where status<>'Cancelled' and order_date between p_from and p_to;
 select coalesce(sum(amount),0) into collected from public.lm_order_payments where not voided and payment_date between p_from and p_to;
 select coalesce(sum(greatest(0,o.amount-coalesce((select sum(p.amount) from public.lm_order_payments p where p.order_id=o.id and not p.voided and p.payment_date<=p_to),0))),0) into outstanding from public.lm_orders o where o.status<>'Cancelled' and o.order_date<=p_to;
 return jsonb_build_object('from',p_from,'to',p_to,'sales',sales,'collected',collected,'outstanding',outstanding);
end $$;
create function public.lm_range_money(p_from date,p_to date) returns jsonb language sql stable security invoker set search_path='' as $$select lm_private.range_money(p_from,p_to);$$;
revoke all on function lm_private.range_money(date,date),public.lm_range_money(date,date) from public,anon;
grant execute on function lm_private.range_money(date,date),public.lm_range_money(date,date) to authenticated;
