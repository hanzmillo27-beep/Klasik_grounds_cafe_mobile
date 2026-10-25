# Chosen-item redemption backend update

The mobile app calls `POST /api/Loyalty/redeemItem`. A backend without that
method returns HTTP 404 with an HTML `Page not found.` response. This caused
the error shown in the item chooser; it did not indicate an expired session.

`backend.patch` adds the missing route and cashier fulfillment to the PHP
backend at `C:\xampp\htdocs\sample`, based on commit `fb595c1`. It replaces the
older standalone model/controller snapshots, which did not include the current
cashier reward usage workflow. Apply this patch to the matching backend source
instead of copying old complete files over newer work.

The update was committed and pushed to the backend repository as `3c75ff1`,
and migration `037_loyalty_item_redemption.sql` was applied to the configured
PostgreSQL database on October 25, 2026.

## Apply to a matching backend checkout

```powershell
git apply --check C:/klasik_grounds/backend/loyalty_item_redemption/backend.patch
git apply C:/klasik_grounds/backend/loyalty_item_redemption/backend.patch
php -d extension=php_pdo_pgsql.dll scripts/migrate.php 037_loyalty_item_redemption.sql
```

Run those commands from the backend repository. The migration adds nullable
`product_id` and `product_name` snapshot columns, preserves existing vouchers,
and is safe to rerun. Apply it before deploying the updated PHP files. On PHP
installations with PostgreSQL enabled already, omit the `-d extension` option.

Deploy the backend commit to Render after the migration. Existing APK 1.0.1 can
use the newly available route; APK 1.0.2 also improves missing-route and
authentication error messages. Do not fall back to `/api/Loyalty/redeem`: that
legacy route ignores the selected product and issues a generic coffee voucher.

## API and cashier behavior

The new route requires a `loyal_customer` PHP session and JSON such as
`{"product_id":12}`. The server validates the catalog item and stock, deducts
exactly 10 points, and saves the selected product and voucher in one transaction.
Success is HTTP 200:

```json
{
  "status": "success",
  "message": "Item redeemed. Show the reward code to the cashier.",
  "data": {
    "reward_code": "GC-12AB34CD",
    "points": 15,
    "points_spent": 10,
    "product_id": 12,
    "product_name": "Buffalo Wings"
  }
}
```

Invalid input, insufficient points, and unavailable items return HTTP 400 JSON.
Missing sessions return 401, unauthorized roles return 403, and an authenticated
request using the wrong HTTP method returns 405. No automatic POST retry occurs.
After an uncertain connection failure, check loyalty activity before spending
another 10 points.

The cashier retrieves a chosen-item code through `GET /api/POS/reward/{code}`.
Only the saved product is offered, including food or other non-coffee categories.
Checkout requires that product with quantity one and no payment, then marks the
voucher used while deducting ingredient stock in the same transaction. A failed
checkout leaves stock and voucher usage unchanged; an identical checkout retry
returns its saved receipt. Legacy generic coffee vouchers keep their existing
coffee eligibility and single-use checks.

Issuing a voucher validates stock without reserving or consuming it. Summary
activity retains the product name snapshot, code, and available/used status.

## Verification

Run from the patched backend:

```powershell
php tests/loyalty_item_rewards.php
php tests/loyalty_rewards.php
php tests/loyalty_checkout.php
php tests/fr_023.php
php tests/fr_027.php
```

These tests use an in-memory SQLite database. For the PostgreSQL variant, use
the existing isolated-schema runner, for example:

```powershell
php -d extension=php_pdo_pgsql.dll -d auto_prepend_file=tests/postgres.php tests/loyalty_item_rewards.php
```

That runner creates and removes a randomly named test schema; it does not use
production customer rows or issue real customer vouchers.
