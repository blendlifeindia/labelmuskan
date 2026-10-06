# Label Muskan Studio

Private operations dashboard at https://labelmuskan.online. Warm blush/ivory interface with plum actions and pastel lavender, sage, peach and dusty pink states. Six sections: Home, Orders, Money, More, Clients, Studio. Phone navigation shows all six in one row with 44px-high targets; mobile record tables become labelled vertical cards. No graphs or bank syncing.

## Approved infrastructure

GitHub `blendlifeindia/labelmuskan`, Supabase `xybqwszhkbiucgextwog`, RackNerd VPS `107.173.55.162`, domain `labelmuskan.online`. See AGENTS.md. Private SSH credentials remain in ignored `.deployment/`. The browser contains only a public Supabase publishable key.

## Daily use

- Home: phone-first daily checklist, upcoming delivery/fitting cards (four initially, with View all), compact order counts and three monthly figures: sales, collected, client outstanding. No Home tables, production block or business costs. Tasks can link to a client, order and optional date (blank means today). Other task dates remain in Tasks / Calendar.
- New order: Client → manual order number and blank order date → delivery / fitting → garments → automatic total → advance / balance → Create Order. No payment date/mode, assignments, order notes or per-product delivery overrides are requested at creation. The initial advance uses the entered order date and “Other” payment mode; later receipts use + Add Payment. Extra fields remain in Edit order.
- Orders: multiple garments in one client order, each with its own description, quantity, unit price, fabric, delivery override, production stage and notes. Total is the sum of quantity × price. Overall stage is the earliest unfinished stage across non-cancelled products. Owner can cancel the whole order explicitly.
- Clients: contacts, measurements/date, alteration notes, fitting preferences and current/past orders. Add a new client inside an order using a separate popup; the draft stays intact. A saved client remains if the order draft is cancelled.
- Studio: collection pieces separate from client orders; samples, store, shoots, lookbooks, new designs and store alterations. Karigar jobs link to exactly one client garment or studio piece. Jobs do not automatically change the garment stage or create an expense; record these when they occur.
- Money: mobile month selector, cash summary, and vertical cards for payments, expenses, purchases and reusable salary profiles. Purchases can link to an order, collection or studio piece. Enter each cost once. No bank integration.
- Calendar: simple weekly agenda from deliveries, fitting dates, studio due/shoot dates, karigar deadlines, tasks and manual events.
- More: assigned tasks, calendar, owner-managed team access and optional manual stock register.
- + ADD: permitted daily actions in one menu.

## Roles and access

Only confirmed Supabase logins with studio membership can use the workspace. Muskan is the protected owner. Staff role templates are:

| Role | Default access |
| --- | --- |
| Owner | Everything, including Home and business totals |
| Production | Orders, studio pieces, karigar jobs, tasks, calendar; no prices |
| Team | Tasks they created or that are assigned to them |
| Accounts | Individual payments, expenses, purchases; no Home or aggregate cards |

Owner can override permitted sections in More / Settings → Team access. Home / business overview requires an explicit grant. Orders plus Payments permits creating orders and editing prices. Clients alone shows history without money. Salary access is separate. The app does not create passwords or send invitations: create a confirmed login in Supabase Authentication, then grant the email access here. Removing membership immediately revokes all API access; it retains the login and existing business entries.

Base tables are revoked from browser roles. Public SECURITY INVOKER RPCs call private SECURITY DEFINER functions that check the authenticated user and explicit permissions, whitelist writes, redact money columns, scope tasks/events to their creator/assignee, and protect owner membership. RLS is enabled on every operational table. Authorization never trusts user-editable account metadata. Existing payment triggers lock their source order/salary to prevent concurrent overpayments. Anonymous users cannot execute these RPCs.

## Numbers and dates

India time; weeks start Monday. Money sales use the selected month's order dates, excluding cancelled orders. Collected uses actual client payment dates and ignores voids. Client outstanding is the balance of orders entered through the selected month end, after receipts through that date. Salary totals use actual recorded salary payment dates, including advances; direct Salary-category expenses are included once. Purchase totals use actual purchase payments, excluding unpaid balances. Other expenses use expense dates, excluding Salary entries. Total money out = salaries + purchases + other expenses; Net = collected − total money out. Enter each payment once.

Salary profiles remember name, amount, frequency and payment day. Record Paid adds a dated payment without creating a new profile. Weekly status on the current month refers to the current week; historical cards show recorded payment count and total. Existing salary periods and payments are preserved, with payments copied into the new ledger once. Existing Paid purchases receive a payment on their purchase date; historical Part paid purchases require recording their actual payments because the old system did not store those amounts/dates.

Individual orders offer Invoice → Print / Save PDF. The minimal couture template uses actual outfits, totals and non-void receipts. It defaults to Label Muskan and labelmuskan.online; it does not invent GST, taxes or contact details.

Advances and subsequent receipts form one payment history. Payment amounts must be positive and cannot exceed the outstanding balance. Incorrect payments can be voided, preserving history. Orders/salary values cannot be lowered below already received/paid amounts. Product removal is blocked when a karigar job references it; retain the product or change its job link first.

Workspace RPCs return permitted rows as aggregated JSON without the REST 1,000-row cap. This is suitable for this small studio; introduce server pagination when the dataset grows. Refresh and returning to the tab fetch current permissions and records. Sessions remain in the current tab and refresh access tokens as needed.

## Development / verification

Node 22+, no dependencies: `npm start`, `npm run check`, `npm test`. `node tests/preview.mjs` serves synthetic UI data on port 3001 and never contacts Supabase. Log in with `owner@local.test`, `production@local.test`, `accounts@local.test`, or `team@local.test` and any synthetic password. `tests/access.sql` checks real role enforcement, price redaction, direct-table denial, multi-product totals, overpayment guards, explicit Home grants, assignment scope and access revocation in a rolled-back transaction.

Migrations 001, 002, 003, 004, then the timestamped mobile_home_task_clients migration apply once to the approved database. Migration 003 preserves existing orders, clients, receipts and expenses, migrating each old order into one product. Old production and alteration records remain retained. UI verification uses local synthetic data; none is seeded into production.

## Deployment

Nginx serves `/var/www/labelmuskan-current`, a symlink to a versioned directory in `/var/www/labelmuskan-releases/`. Upload public files into a new release, check them, then switch the symlink atomically. Preserve the existing Nginx TLS configuration and Certbot renewal. Original releases remain available. Database migration 003 requires the corresponding RPC frontend; rolling back only the static UI to an earlier direct-table version will not work.


More → Planned modules offers 38 optional ideas across seven studio categories, with scenario labels, Build next / Consider later selections and a downloadable shortlist. This is an owner-only planning catalogue, not activated functionality. Choices are stored per signed-in owner on the current device and do not sync between devices. The larger, stronger text retains the six-item phone navigation.
