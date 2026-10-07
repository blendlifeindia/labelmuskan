import test from 'node:test';
import assert from 'node:assert/strict';
import {sortOrdersByInvoice} from '../public/domain.js';
test('invoice ordering is numeric, ignores delivery urgency and puts missing numbers last',()=>{
 const rows=[{id:'a',invoice_number:'LM-2026-10',due_date:'2026-01-01'},{id:'b',invoice_number:'LM-2026-2',due_date:'2026-12-01'},{id:'c',invoice_number:null},{id:'d',invoice_number:'LM-2025-100'}];
 assert.deepEqual(sortOrdersByInvoice(rows).map(o=>o.id),['d','b','a','c']);
 assert.deepEqual(rows.map(o=>o.id),['a','b','c','d']);
});
