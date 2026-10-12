alter table public.lm_tasks add column completed_at timestamptz;
update public.lm_tasks set completed_at=now() where done;
create function lm_private.task_completion_time() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if new.done then
  if tg_op='INSERT' then new.completed_at:=now();
  elsif not old.done then new.completed_at:=now();
  else new.completed_at:=old.completed_at;end if;
 else new.completed_at:=null;end if;
 return new;
end $$;
revoke all on function lm_private.task_completion_time() from public,anon,authenticated;
create trigger lm_task_completion_time before insert or update on public.lm_tasks for each row execute function lm_private.task_completion_time();
