import test from 'node:test';
import assert from 'node:assert/strict';
import {sortOrdersByInvoice} from '../public/domain.js';
test('invoice ordering is numeric, ignores delivery urgency and puts missing numbers last',()=>{
 const rows=[{id:'a',invoice_number:'LM-2026-10',due_date:'2026-01-01'},{id:'b',invoice_number:'LM-2026-2',due_date:'2026-12-01'},{id:'c',invoice_number:null},{id:'d',invoice_number:'LM-2025-100'}];
 assert.deepEqual(sortOrdersByInvoice(rows).map(o=>o.id),['d','b','a','c']);
 assert.deepEqual(rows.map(o=>o.id),['a','b','c','d']);
});

import {sortOrdersRecent} from '../public/domain.js';
test('recent orders use descending order date, then creation time',()=>{
 const rows=[{id:'old',order_date:'2026-09-30',invoice_number:'LM-2026-999'},{id:'new',order_date:'2026-10-07',created_at:'2026-10-07T12:00:00Z'},{id:'earlier',order_date:'2026-10-07',created_at:'2026-10-07T09:00:00Z'},{id:'blank'}];
 assert.deepEqual(sortOrdersRecent(rows).map(o=>o.id),['new','earlier','old','blank']);
});
