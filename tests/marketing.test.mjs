import test from 'node:test';
import assert from 'node:assert/strict';
import {marketingOverview,marketingMatches} from '../public/marketing.js';
test('collaboration overview counts actual statuses and search covers saved details',()=>{const rows=[{influencer_name:'Ananya',outfit_name:'Drape skirt',agency_name:'Studio Agency',status:'Sent'},{status:'Posted'},{status:'Returned'},{status:'Planned'}];assert.deepEqual(marketingOverview(rows),{total:4,sent:1,completed:2});assert.equal(marketingMatches(rows[0],'AGENCY'),true);assert.equal(marketingMatches(rows[0],'cape'),false);});
