begin;
create or replace function lm_private.workspace() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb:='{}';s public.lm_staff; rows jsonb; financial boolean;day date:=(now() at time zone 'Asia/Kolkata')::date;month_start date;month_end date; sales numeric;collected numeric;outstanding numeric;costs numeric;begin
 select * into s from public.lm_staff where user_id=auth.uid();
 if not found then raise insufficient_privilege using message='Your account has not been approved for studio access';end if;
 financial=lm_private.can('payments');
 result=jsonb_build_object('profile',jsonb_build_object('user_id',s.user_id,'role',s.role,'name',s.display_name,'permissions',s.permissions),'people',(select coalesce(jsonb_agg(jsonb_build_object('user_id',user_id,'name',coalesce(display_name,'Team member'))),'[]') from public.lm_staff));
 if lm_private.can('orders') or lm_private.can('clients') or financial or lm_private.can('calendar') or lm_private.can('production') or lm_private.can('home') then
  select coalesce(jsonb_agg((case when financial then to_jsonb(o) else to_jsonb(o)-array['amount','paid','payment_due_date'] end)||jsonb_build_object('next_delivery',coalesce((select min(coalesce(i.due_date,o.due_date)) from public.lm_order_items i where i.order_id=o.id and i.status not in ('Delivered','Cancelled')),o.due_date))),'[]') into rows from public.lm_orders o;
  result=result||jsonb_build_object('orders',rows);
  select coalesce(jsonb_agg(case when financial then to_jsonb(i) else to_jsonb(i)-'price' end order by i.position),'[]') into rows from public.lm_order_items i;
  result=result||jsonb_build_object('order_items',rows);
 end if;
 if lm_private.can('clients') then result=result||jsonb_build_object('customers',(select coalesce(jsonb_agg(to_jsonb(c)),'[]') from public.lm_customers c));end if;
 if lm_private.can('studio') or lm_private.can('production') or lm_private.can('purchases') or lm_private.can('calendar') or lm_private.can('home') then result=result||jsonb_build_object('studio_pieces',(select coalesce(jsonb_agg(to_jsonb(p)),'[]') from public.lm_studio_pieces p));end if;
 if lm_private.can('production') or lm_private.can('calendar') or lm_private.can('home') then result=result||jsonb_build_object('jobs',(select coalesce(jsonb_agg(case when lm_private.can('expenses') then to_jsonb(j) else to_jsonb(j)-'payment_status' end),'[]') from public.lm_jobs j));end if;
 if lm_private.can('tasks') or lm_private.can('home') or lm_private.can('calendar') then
  result=result||jsonb_build_object('tasks',(select coalesce(jsonb_agg(to_jsonb(t)),'[]') from public.lm_tasks t where s.role='owner' or t.assigned_user_id=s.user_id or t.created_by=s.user_id));
 end if;
 if lm_private.can('calendar') or lm_private.can('home') then result=result||jsonb_build_object('events',(select coalesce(jsonb_agg(to_jsonb(e)),'[]') from public.lm_events e where s.role='owner' or e.assigned_user_id=s.user_id or e.created_by=s.user_id));end if;
 if financial then result=result||jsonb_build_object('order_payments',(select coalesce(jsonb_agg(to_jsonb(p)),'[]') from public.lm_order_payments p));end if;
 if lm_private.can('expenses') then result=result||jsonb_build_object('expenses',(select coalesce(jsonb_agg(to_jsonb(e)),'[]') from public.lm_expenses e));end if;
 if lm_private.can('purchases') then result=result||jsonb_build_object('purchases',(select coalesce(jsonb_agg(to_jsonb(p)),'[]') from public.lm_purchases p));end if;
 if lm_private.can('salaries') then result=result||jsonb_build_object('salaries',(select coalesce(jsonb_agg(to_jsonb(payroll)),'[]') from public.lm_salaries payroll),'salary_payments',(select coalesce(jsonb_agg(to_jsonb(p)),'[]') from public.lm_salary_payments p));end if;
 if lm_private.can('orders') then result=result||jsonb_build_object('alterations',(select coalesce(jsonb_agg(case when lm_private.can('expenses') then to_jsonb(a) else to_jsonb(a)-'additional_cost' end),'[]') from public.lm_alterations a));end if;
 if s.role='owner' then result=result||jsonb_build_object('inventory',(select coalesce(jsonb_agg(to_jsonb(i)),'[]') from public.lm_inventory i),'members',(select coalesce(jsonb_agg(jsonb_build_object('user_id',st.user_id,'role',st.role,'permissions',st.permissions,'name',st.display_name,'email',u.email)),'[]') from public.lm_staff st join auth.users u on u.id=st.user_id));end if;
 if lm_private.can('home') then
  month_start=date_trunc('month',day)::date;month_end=(month_start+interval '1 month')::date;
  select coalesce(sum(amount),0) into sales from public.lm_orders where status<>'Cancelled' and order_date>=month_start and order_date<month_end;
  select coalesce(sum(amount),0) into collected from public.lm_order_payments where not voided and payment_date>=month_start and payment_date<month_end;
  select coalesce(sum(greatest(0,o.amount-coalesce((select sum(p.amount) from public.lm_order_payments p where p.order_id=o.id and not p.voided),0))),0) into outstanding from public.lm_orders o where o.status<>'Cancelled';
  costs=coalesce((select sum(amount) from public.lm_expenses where expense_date>=month_start and expense_date<month_end),0)+coalesce((select sum(amount) from public.lm_purchases where purchase_date>=month_start and purchase_date<month_end),0)+coalesce((select sum(salary-deduction) from public.lm_salaries where period_start>=month_start and period_start<month_end),0)+coalesce((select sum(additional_cost) from public.lm_alterations where status<>'Cancelled' and received_date>=month_start and received_date<month_end),0);
  result=result||jsonb_build_object('home',jsonb_build_object('sales',sales,'collected',collected,'outstanding',outstanding,'costs',costs));
 end if;
 return result;
end $$;
commit;
