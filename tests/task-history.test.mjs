import test from 'node:test';
import assert from 'node:assert/strict';
import {visibleTasks,archivedTasks} from '../public/task-view.js';
test('unfinished and completed tasks persist indefinitely; history shows completed tasks',()=>{
 const tasks=[{id:'old',done:false,task_date:'2026-03-01'},{id:'future',done:false,task_date:'2026-11-01'},{id:'done',done:true,completed_at:'2026-03-01T00:00:00Z'}];
 assert.deepEqual(visibleTasks(tasks).map(t=>t.id),['old','future','done']);
 assert.deepEqual(archivedTasks(tasks).map(t=>t.id),['done']);
 assert.deepEqual(archivedTasks([{...tasks[2],done:false}]),[]);
 assert.deepEqual(tasks.map(t=>t.id),['old','future','done']);
});
