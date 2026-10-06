// Optional future features; choosing one never enables integrations or changes business data.
export const moduleGroups=[
 {name:'Clients & appointments',modules:[
 ['appointments','Appointments','Book consultations, fittings and collection visits.','Custom · Bridal · Ready-to-wear'],
 ['measurements','Measurement profiles','Versioned measurements, reference photos and fitting history.','Custom · Bridal'],
 ['client-portal','Client portal','Clients can view approved order progress and fitting dates.','Custom · Bridal · Ready-to-wear'],
 ['follow-ups','Client follow-ups','Track enquiries, quotes and follow-up reminders.','All studio work'],
 ['occasions','Occasion planner','Keep wedding dates, functions and coordinated outfits together.','Bridal · Occasionwear']
 ]},
 {name:'Design & orders',modules:[
 ['quotations','Quotations','Prepare estimates and convert approved quotes into orders.','Custom · Bridal · Wholesale'],
 ['design-library','Design library','Save sketches, mood boards, references and previous designs.','Custom · Collections'],
 ['approvals','Design approvals','Track client approval of fabric, design and final details.','Custom · Bridal'],
 ['packages','Outfit packages','Manage bridal trousseaux and coordinated multi-look orders.','Bridal · Occasionwear'],
 ['returns','Returns & exchanges','Track alterations, exchanges and returned products.','Ready-to-wear · Retail'],
 ['dispatch','Dispatch & couriers','Track packing, collection, shipping and delivery confirmation.','All deliveries']
 ]},
 {name:'Production & quality',modules:[
 ['production-board','Production board','A visual stage-by-stage view of garments and deadlines.','Custom · Bridal · Collections'],
 ['job-costs','Karigar job costing','Track agreed job charges and actual production costs.','Tailoring · Embroidery · Dyeing'],
 ['quality','Quality checklist','Check finishing, measurements and packing before delivery.','All garments'],
 ['capacity','Capacity planner','See workload by tailor and spot overloaded weeks.','Custom · Collections'],
 ['rework','Rework tracking','Record fitting changes, rework reasons and completion.','Fittings · Alterations']
 ]},
 {name:'Fabric, stock & purchasing',modules:[
 ['fabric-library','Fabric library','Track fabric, colour, supplier and swatch references.','Custom · Collections'],
 ['fabric-consumption','Fabric consumption','Allocate fabric to outfits and track remaining material.','Custom · Batch production'],
 ['purchase-orders','Purchase orders','Create supplier requests and follow incoming deliveries.','Fabric · Trims · Packaging'],
 ['stock-alerts','Stock alerts','Highlight low stock and materials needing a reorder.','Fabric · Finished goods'],
 ['supplier-directory','Supplier directory','Keep supplier contacts, prices and purchase history.','All purchasing'],
 ['stock-movements','Stock movements','Record receipts, transfers, usage and adjustments.','Studio · Retail · Wholesale']
 ]},
 {name:'Money & team',modules:[
 ['budgets','Order budgets','Compare estimated and actual costs per order.','Custom · Bridal · Collections'],
 ['profitability','Profitability','Understand order and collection margins from recorded costs.','All sales'],
 ['cash-forecast','Cash-flow forecast','Compare upcoming collections and expected payments.','All studio work'],
 ['reimbursements','Reimbursements','Review staff-paid expenses and track repayments.','Team expenses'],
 ['attendance','Attendance & leave','Track attendance, leave and payroll inputs.','Studio team'],
 ['team-checklists','Team checklists','Repeat opening, closing, packing and maintenance routines.','Daily studio operations']
 ]},
 {name:'Collections & growth',modules:[
 ['collection-planner','Collection planner','Plan launches, samples, looks and production targets.','Collections · Ready-to-wear'],
 ['shoot-planner','Shoot planner','Organise looks, shoot dates, teams and content requirements.','Campaigns · Collections'],
 ['wholesale','Wholesale orders','Track bulk orders, quantities, buyer commitments and dispatch.','Wholesale · Retail partners'],
 ['sales-channels','Sales channels','Compare studio, online and partner sales.','Studio · Online · Retail'],
 ['reports','Studio reports','Simple monthly summaries and exportable operational reports.','Owner overview']
 ]},
 {name:'Optional integrations',modules:[
 ['whatsapp','WhatsApp reminders','Send approved appointment and order updates through a connected service.','Requires separate setup'],
 ['online-store','Online store connection','Connect product listings and online orders to studio work.','Requires separate setup'],
 ['payment-links','Payment links','Offer client payment links and match confirmed receipts.','Requires separate setup'],
 ['calendar-sync','Calendar sync','Sync appointments with a chosen external calendar.','Requires separate setup'],
 ['accounting-export','Accounting export','Export recorded transactions for your accountant.','Requires chosen export format']
 ]}
];
export const plannedModules=moduleGroups.flatMap(g=>g.modules.map(([id,title,description,scenario])=>({id,title,description,scenario,group:g.name})));
export function shortlistText(choices){return ['LABEL MUSKAN · PLANNED MODULES','',...plannedModules.filter(m=>choices[m.id]).map(m=>`${choices[m.id]==='next'?'NEXT':'LATER'} · ${m.title}\n${m.description}\nFor: ${m.scenario}\n`),'These are planning choices, not enabled features.'].join('\n');}
