# Label Muskan operations

Private staff dashboard for orders, production, inventory, customers, and expenses. Uses Supabase Auth and Postgres with row-level security; static frontend served by Nginx on the RackNerd VPS.

## Approved infrastructure

- GitHub: https://github.com/blendlifeindia/labelmuskan
- Supabase: https://supabase.com/dashboard/project/xybqwszhkbiucgextwog
- VPS: 107.173.55.162 (Ubuntu 24.04)
- Domain: https://labelmuskan.online

## Local preview

Run `npm start` with Node 22 or newer. No npm packages are needed. `npm run check` checks JavaScript syntax.

`public/config.js` contains only the public Supabase publishable key. Never add a service-role key to the frontend. SSH credentials stay in the ignored `.deployment/` directory.

## Staff access

Create a confirmed user through Supabase Authentication. Then add the user's UUID to `public.lm_staff` through the Supabase dashboard or an authorized SQL connection. Only allowlisted staff can read or write operational data. Anonymous users cannot access operational tables. Staff cannot modify their own access membership. All approved staff have the same operational access in this initial version.

## Database

The initial schema is recorded in `supabase/migrations/001_operations.sql`. Apply it once to the approved project. Do not rerun against an initialized database. No sample business records are seeded.

## Deployment

Install Nginx and Certbot on the VPS. Copy the contents of `public/` to `/var/www/labelmuskan/`. Install `deploy/nginx.conf` in `/etc/nginx/sites-available/labelmuskan`, enable it via a symlink in `sites-enabled`, run `nginx -t`, and reload Nginx. Once DNS resolves, run Certbot with the Nginx plugin for the apex domain and, if configured, `www`.

## Initial scope

Add and edit records in all five sections. Overview shows open orders, outstanding payments, production jobs, monthly expenses, and low-stock alerts. Order and production references are entered manually; inventory quantities are updated manually. Financial totals use INR. Data loads the latest 1,000 records per section; use Refresh to retrieve changes made by other staff. The browser session is stored only for the current tab. No deletion, automated stock deduction, imports, attachments, or multi-role permissions in this initial version.
