begin;
alter table public.lm_expenses drop constraint lm_expenses_category_check;
update public.lm_expenses set category='Miscellaneous' where category='Other';
alter table public.lm_expenses add constraint lm_expenses_category_check check(category in ('Salary','Karigar','Fabric','Dye','Packaging','Studio','Marketing/PR','Courier','Miscellaneous'));
-- One snapshot preserves the garment stages for an accidental delivery reversal.
alter table public.lm_orders add column delivery_previous_stages jsonb;
create function lm_private.set_order_delivery(p_id uuid,p_delivered boolean) returns jsonb language plpgsql security definer set search_path='' as $$
declare o public.lm_orders;snapshot jsonb;begin
 if auth.uid() is null or not lm_private.is_staff() or not lm_private.can('orders') then raise insufficient_privilege using message='Orders access required';end if;
 if p_delivered is null then raise exception 'Choose a delivery action';end if;
 select * into o from public.lm_orders where id=p_id for update;
 if not found then raise exception 'Order is unavailable';end if;
 if o.status='Cancelled' then raise exception 'Cancelled orders cannot be delivered';end if;
 perform 1 from public.lm_order_items where order_id=p_id for update;
 if p_delivered then
  if o.status='Delivered' then return jsonb_build_object('saved',true);end if;
  snapshot=jsonb_build_object('order_status',o.status,'items',coalesce((select jsonb_object_agg(id::text,status) from public.lm_order_items where order_id=p_id),'{}'::jsonb));
  update public.lm_order_items set status='Delivered' where order_id=p_id and status<>'Cancelled';
  update public.lm_orders set status='Delivered',delivery_previous_stages=snapshot where id=p_id;
 else
  if o.status<>'Delivered' then raise exception 'This order is not marked Delivered';end if;
  update public.lm_order_items i set status=coalesce(o.delivery_previous_stages#>>array['items',i.id::text],'Ready') where i.order_id=p_id and i.status='Delivered';
  update public.lm_orders set status=coalesce(o.delivery_previous_stages->>'order_status','Ready'),delivery_previous_stages=null where id=p_id;
 end if;
 return jsonb_build_object('saved',true);
end $$;
create function public.lm_set_order_delivery(p_id uuid,p_delivered boolean) returns jsonb language sql security invoker set search_path='' as $$select lm_private.set_order_delivery(p_id,p_delivered)$$;
revoke all on function lm_private.set_order_delivery(uuid,boolean),public.lm_set_order_delivery(uuid,boolean) from public,anon,authenticated;
grant execute on function lm_private.set_order_delivery(uuid,boolean),public.lm_set_order_delivery(uuid,boolean) to authenticated;
commit;
