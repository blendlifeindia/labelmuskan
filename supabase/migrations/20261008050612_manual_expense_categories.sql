alter table public.lm_expenses drop constraint lm_expenses_category_check;
alter table public.lm_expenses add constraint lm_expenses_category_check check(length(trim(category)) between 1 and 80);
do $$ declare definition text; begin
select pg_get_functiondef('lm_private.save_expense_batch(jsonb,text,text,text)'::regprocedure) into definition;
definition:=replace(definition, 'row->>''category'' not in (''Salary'',''Karigar'',''Fabric'',''Dye'',''Packaging'',''Studio'',''Marketing/PR'',''Courier'',''Miscellaneous'')','length(trim(row->>''category'')) not between 1 and 80');
if position('not in (''Salary''' in definition)>0 then raise exception 'Expense validation replacement failed';end if;
execute definition;
end $$;
