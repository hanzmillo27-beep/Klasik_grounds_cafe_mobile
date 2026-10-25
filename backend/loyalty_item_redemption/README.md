# Item redemption backend patch

This patch extends the PHP backend inspected at `C:\xampp\htdocs\sample`.
It has not been applied to that checkout, a database, or the Render service.

## Deploy

1. Apply `migrations/031_loyalty_item_redemption.sql` to the backend PostgreSQL
   database. It adds nullable product ID and product name snapshot columns;
   existing free-coffee rewards remain valid. The migration is safe to rerun.
2. Copy these files into the backend repository at the same relative paths:
   - `app/Models/Loyalty.php` -> `C:\xampp\htdocs\sample\app\Models\Loyalty.php`
   - `app/api/Loyalty/LoyaltyController.php` -> `C:\xampp\htdocs\sample\app\api\Loyalty\LoyaltyController.php`
3. Deploy those PHP changes to the server used by Flutter (currently Render).
   A local file copy alone does not update Render. No router or role-map change
   is needed: the existing router discovers the new public controller method,
   and the existing `loyal_customer` permission applies.

Run the migration before deploying the model: the updated activity query uses
the new snapshot column. This patch targets the current PostgreSQL backend;
the older MySQL `loyalty_setup.sql` in that checkout is not the migration target.

## API contract

`POST /api/Loyalty/redeemItem`, authenticated with a `loyal_customer` PHP session:

```json
{"product_id": 12}
```

`product_id` must be a positive JSON integer. The authenticated customer ID,
catalog item name, and fixed 10-point cost are determined by the server.
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
    "product_name": "Chocolate cookie"
  }
}
```

Invalid JSON, invalid/missing/unavailable items, or insufficient points return
HTTP 400 with `{"status":"error","message":"..."}`. Wrong method returns 405.
Existing route authorization handles missing/unauthorized sessions with 401/403.
The new route is deliberately separate from `/api/Loyalty/redeem`: an older
server must not silently ignore the chosen item and spend points on a generic
coffee voucher. The legacy `/redeem` method remains available unchanged.

The points row and chosen product are locked while validating and saving.
Point deduction and the selected item voucher are committed together or rolled
back together. Any active, manually available item with sufficient ingredients
at redemption time can be chosen, regardless of category or price. Product names
are snapshotted so renamed/deleted catalog items do not change prior rewards.
`GET /api/Loyalty/summary` includes the saved item name as activity `description`
and the existing `reward_code`; legacy entries keep `Free coffee reward`.

Vouchers follow the existing workflow: show the saved item and code to the
cashier. This patch validates stock without reserving/consuming it, placing a
kiosk order, or adding automatic cashier voucher consumption. The backend has
no existing endpoint to mark vouchers used; cashier fulfillment remains manual.
There is no automatic POST retry: a connection failure after commit must be
checked through loyalty activity before spending another 10 points.

## Verification

Run from this directory with PHP 8 and PDO SQLite:

```powershell
php -l app/Models/Loyalty.php
php -l app/api/Loyalty/LoyaltyController.php
php tests/redeem_item_test.php
```

The tests use an in-memory SQLite database and never load production credentials
or connect to the cafe database. `tests/Model.php` and
`tests/ProductAvailability.php` are unmodified dependency snapshots from the
inspected backend, used only as test fixtures. Do not deploy the `tests` folder.
SQLite checks cover transactional rollback, guarded balance updates, repeated
10-point spending, catalog/stock rejection, immutable history, and the real
controller's JSON validation. Production row-lock concurrency requires a
PostgreSQL integration check after deployment; it is not simulated by SQLite.
