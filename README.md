# Label Muskan studio operations

Private daily operations dashboard at https://labelmuskan.online. Built around orders and delivery urgency, with simple forms and automatic balances and summaries. No graphs or separate production entry are needed.

## Approved infrastructure

- GitHub: https://github.com/blendlifeindia/labelmuskan
- Supabase: https://supabase.com/dashboard/project/xybqwszhkbiucgextwog
- RackNerd Ubuntu VPS: 107.173.55.162
- Domain: labelmuskan.online (Spaceship DNS)

See AGENTS.md for connection restrictions. Private SSH credentials stay in ignored `.deployment/`; never commit them. `public/config.js` contains only a public publishable key. No service-role keys are used in the browser.

## Daily workflow

1. **New order:** choose an existing client or add a client inside the same form. Enter order and delivery dates, outfit, selling price, production stage, assigned staff, and any advance received. The client, order, and advance are saved in one database transaction.
2. **Orders:** automatically sorted by earliest delivery date. Use Pending, Today, Next 3 days, Overdue, or All. Open an order to update production, record another payment, or inspect direct costs and gross profit.
3. **Expenses:** daily studio expenses with category, paid-by, payment mode, and optional order link. Enter materials in Purchases and payroll in Salaries, rather than repeating the same cost here.
4. **Purchases:** record materials with vendor, category, quantity, amount, payment status, and optional order link. Stock purchases can stay unallocated. The amount enters monthly costs once.
5. **Salaries:** create one record per staff member and weekly/monthly pay period. Record salary payments and advances against that period. Salary less deduction is the obligation; both salary payments and advances reduce its balance.
6. **Clients:** contact details, Instagram, measurements, preferences, notes, order history, total orders, and total spent. Previous client information is reused for new orders.
7. **Alterations & returns:** choose the order; its client is reused. Track the issue, received date, assigned person, expected completion, status, and studio cost. The added cost enters order/monthly costs once, so do not repeat it in Expenses.
8. **Inventory:** a basic manual stock register with colour, quantity, unit cost, vendor, and low-stock threshold. Automated material purchase/use movements can be added later.

## Calculations

All dates use India time; weeks start Monday. Monthly sales use the order date and exclude cancelled orders. The monthly summary shows both payments allocated to that month's orders (including payments received in another month) and actual cash collected during the selected month. Outstanding comes from non-voided payment records, never a manually entered balance.

Costs include purchases and expenses by their entry dates, salary less deductions by the month the pay period starts, and alteration cost by received date. Unpaid purchases count as incurred cost. Payroll payments and advances are not added as another expense. Monthly profit is estimated sales minus these recorded costs, before tax, inventory valuation, and overhead allocations. Order gross profit includes linked direct purchases, expenses, and alteration costs, excluding unallocated salaries and overheads.

Payment amounts must be positive and cannot exceed the remaining balance. A mistaken payment can be voided from its history; the entry remains recorded. New-record forms use stable UUIDs to avoid duplicates on retries. Salary and order values cannot be reduced below payments already made.

All data is fetched in pages rather than silently capped at 1,000 records. Saved records refresh all totals immediately. Refresh or returning to the tab retrieves changes by other staff. A browser session lasts for the current tab and refreshes its access token as needed.

## Access and database

Only confirmed Supabase users added to `public.lm_staff` can access operations. Staff cannot change their own membership. All approved staff share operational access in this version. Row-level security protects every operational table; anonymous access is blocked. The order-creation RPC runs as the caller under the same policies. Payment triggers lock the source order or salary period to prevent concurrent overpayments.

Apply `supabase/migrations/001_operations.sql` then `002_studio_operations.sql` once on a fresh approved database. The original production table is retained for compatibility; production is now stored on orders. No real or synthetic business records are seeded into production.

## Development and verification

Node 22+; no package installation is needed.

- `npm start`: local server at http://127.0.0.1:3000
- `npm run check`: syntax checks
- `npm test`: financial calculations, dates, and delivery sorting
- `node tests/preview.mjs`: local UI test at http://127.0.0.1:3001 using synthetic data only; it never connects to Supabase
- `tests/access.sql`: rolled-back database checks for staff workflows, overpayment guards, atomic order creation, and nonstaff denial

The local preview accepts a synthetic email/password and serves fake Auth/API routes for UI testing. Never deploy that test server. Only `public/` is hosted.

## Deployment

Nginx serves the release selected by `/var/www/labelmuskan-current`, currently `/var/www/labelmuskan-releases/20261005-studio/`. Copy all files in `public/` together to a new release directory, then atomically update the current symlink. The original frontend remains in `/var/www/labelmuskan/` for recovery. `deploy/nginx.conf` provides the initial HTTP configuration; the live VPS configuration includes the release root and Certbot-managed TLS. Do not overwrite its certificate settings when deploying frontend updates. HTTPS renewal runs through `certbot.timer`; the renewal dry run passed during initial setup.

The full user brief is saved in `requirements/studio-dashboard.txt`.
