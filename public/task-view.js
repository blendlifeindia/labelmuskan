// Tasks stay on Home until explicitly deleted, regardless of date or completion.
export const visibleTasks=rows=>[...rows].sort((a,b)=>Number(a.done)-Number(b.done)||String(a.task_date||'').localeCompare(String(b.task_date||'')));
export const archivedTasks=rows=>rows.filter(t=>t.done).sort((a,b)=>String(b.completed_at||'').localeCompare(String(a.completed_at||'')));
