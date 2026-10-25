# Klasik Grounds Cafe

Flutter cafe app connected to the Render web API at `https://klasik-grounds-cafe.onrender.com`. It supports guest menu browsing and kiosk order submission, plus API-backed inventory and loyalty screens for authenticated accounts.

## API connection

`lib/services/api_service.dart` contains the shared HTTP client and API models. The app reads kiosk products from `GET /api/Kiosk/products`, submits kiosk orders to `POST /api/Kiosk/submit`, reads inventory from `GET /api/Inventory/all`, reads recent orders from `GET /api/POS/transactions`, and reads member points from `GET /api/Loyalty/summary`. Authenticated requests use the PHP session cookie from the web login.

Username/password sign-in posts URL-encoded form fields to `/Auth/login` and carries the returned PHP session cookie on later requests. The web login is expected to redirect after success. Logging out clears the local session because no logout route was supplied.

On Android, the app retains the PHP session cookie from the login page and captures the rotated cookie returned by a successful login. It selects `PHPSESSID` when several `Set-Cookie` values are combined. If login redirects back to `/Auth`, the app reads that page once with the current cookie and displays the server's flash error. HTTP 429 responses use the server's `Retry-After` countdown; unavailable sign-in responses show the server's error message. Returning to the login page without an error does not grant access or prove that the credentials were wrong.

Flutter Web requires the Render server to allow the Flutter app's exact origin with credentialed CORS. The current `/Auth` and `/Auth/login` responses do not send `Access-Control-Allow-Origin`, so browser requests fail before the login endpoint runs. Configure CORS on `/Auth`, `/Auth/login`, and `/api/*` with the allowed app origin, `Access-Control-Allow-Credentials: true`, methods `GET, POST, DELETE, OPTIONS`, and headers `Accept, Content-Type`; respond to `OPTIONS` before authentication/redirect handling. PHP session cookies must use `SameSite=None; Secure; HttpOnly; Path=/` for cross-site web requests. Native Android/iOS builds do not enforce browser CORS.

The kiosk submit request matches the cafe's public `js/Kiosk.js`: multipart form fields include `customer_name` and `items`, a JSON-encoded array of `product_id` and `quantity`. The server reports success with `status: "success"`, `reference_code`, and `total_amount`; error responses use `status` and `message`, even when the HTTP status is 200. The app displays the confirmed reference until the customer starts a new order. Orders are paid at the cashier.

Verified against `C:\xampp\htdocs\sample`: `app/Models/Kiosk.php` generates references with `'KG-' . strtoupper(bin2hex(random_bytes(4)))`, saves the reference and order items in a transaction, then returns the reference after commit. `app/api/Kiosk/KioskController.php` returns it as the top-level `reference_code`. Numeric order IDs are not cashier references. The app still targets the Render URL above; local PHP changes require a separate deployment to affect that server.

Recent orders use the POS transactions response: `data` contains `sale_id`, `total_amount`, `sale_date`, and `item_count` (the number of sale lines). The backend returns completed sales newest first; unpaid kiosk orders are not included. The overview loads and refreshes this list for owners and cashiers, as required by the backend's role permissions. `user_id` identifies the cashier, so it is not used to filter customer history. Missing timestamps show as unavailable; timestamps without an offset use the backend's Asia/Manila timezone. Loading errors remain visible in the recent orders section while menu access stays available.

The supplied API has no route for loyalty activity history, so that list is not populated. Product availability is taken from the kiosk products response when present; otherwise products are shown as available and the API remains responsible for validating checkout.

Sign-in attempts are limited to five per rolling minute, and kiosk submissions to one every three seconds. These app-side limits are shared by API clients while the app is running and count requests even when the server rejects them. Invalid kiosk forms do not consume an attempt. Sign-in displays a retry countdown; blocked requests are not sent or retried automatically. Limits reset when the app process restarts; server-side enforcement is separate.

## Code layout

- `lib/controller/` - authentication and cafe state
- `lib/home_page/` - sign-in, menu, kiosk, inventory, rewards, and overview screens
- `lib/services/api_service.dart` - HTTP client and response models
- `lib/main.dart` - app theme and local session gate
