import test from 'node:test';
import assert from 'node:assert/strict';
import {fabricTotals,fabricNeedsPurchase} from '../public/fabric-stock.js';
test('fabric ledger excludes voided moves and detects low stock or planned purchases',()=>{
 const f={reorder_metres:2,next_purchase_date:'2026-10-15',moves:[{kind:'Purchased',metres:10},{kind:'Used',metres:8},{kind:'Used',metres:2,voided:true}]};
 assert.deepEqual(fabricTotals(f),{bought:10,used:8,remaining:2});
 assert.equal(fabricNeedsPurchase(f,'2026-10-12'),true);
 assert.equal(fabricNeedsPurchase({...f,reorder_metres:0},'2026-10-12'),false);
 assert.equal(fabricNeedsPurchase({...f,reorder_metres:0},'2026-10-15'),true);
 assert.equal(fabricNeedsPurchase({...f,voided:true},'2026-10-15'),false);
});
