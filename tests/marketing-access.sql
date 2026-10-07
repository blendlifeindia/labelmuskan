-- Synthetic fixtures only; every write is rolled back.
begin;
insert into auth.users(id,email,email_confirmed_at) values ('10000000-0000-4000-8000-000000000099','marketing-test@example.invalid',now());
insert into public.lm_staff(user_id,role,permissions) values ('10000000-0000-4000-8000-000000000099','team',array['tasks']);
set local role authenticated;
select set_config('request.jwt.claim.sub','620ff01b-a3bb-4c91-9242-43a8ce4a49e4',true);
do $$ declare id uuid;w jsonb;begin
 id=(public.lm_save_marketing('{"influencer_name":"Rollback influencer","outfit_name":"Drape set","agency_name":"Agency","sent_through":"Courier","sent_date":"2026-10-07","collaboration":"Barter","status":"Sent","image_data":"data:image/jpeg;base64,/9j/"}',null)->>'id')::uuid;
 w=public.lm_workspace();
 if not exists(select 1 from jsonb_array_elements(w->'influencer_marketing') m where m->>'id'=id::text and m->>'status'='Sent') then raise exception 'Saved collaboration missing';end if;
 perform public.lm_save_marketing('{"influencer_name":"Updated influencer","outfit_name":"Drape set","collaboration":"Sourcing","status":"Posted","image_data":null}',id);
 if not exists(select 1 from jsonb_array_elements(public.lm_workspace()->'influencer_marketing') m where m->>'id'=id::text and m->>'influencer_name'='Updated influencer' and m->>'image_data' is null and m->>'sent_date' is null) then raise exception 'Edit / optional fields failed';end if;
 begin perform public.lm_save_marketing('{"influencer_name":"Bad","outfit_name":"Test","collaboration":"Barter","status":"Sent","image_data":"data:image/svg+xml;base64,AAAA"}',null);raise exception 'SVG accepted';exception when check_violation then null;end;
 begin perform public.lm_save_marketing('{"influencer_name":"Bad","outfit_name":"Test","collaboration":"Barter","status":"Fake"}',null);raise exception 'Invalid status accepted';exception when check_violation then null;end;
 begin perform influencer_name from public.lm_influencer_marketing;raise exception 'Direct table access allowed';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000099',true);
do $$ begin
 if public.lm_workspace()?'influencer_marketing' then raise exception 'Marketing leaked to unassigned staff';end if;
 begin perform public.lm_save_marketing('{}',null);raise exception 'Unassigned write allowed';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub','620ff01b-a3bb-4c91-9242-43a8ce4a49e4',true);
select public.lm_manage_member('marketing-test@example.invalid','team',array['marketing'],'Marketing test');
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000099',true);
do $$ begin
 if not public.lm_workspace()?'influencer_marketing' or public.lm_workspace()?'order_payments' then raise exception 'Explicit marketing grant scope failed';end if;
 perform public.lm_save_marketing('{"influencer_name":"Granted staff","outfit_name":"Cape","collaboration":"Sourcing","status":"Planned"}',null);
end $$;
select 'Marketing create/edit/photos and permission boundaries passed' result;
rollback;
