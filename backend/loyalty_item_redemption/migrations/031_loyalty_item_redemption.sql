-- PostgreSQL, matching the current backend Core/Database.php configuration.
-- Apply before deploying the updated Loyalty model and controller.
-- Nullable snapshots preserve legacy free-coffee vouchers. Intentionally no
-- product foreign key: historical rewards survive catalog deletion.
ALTER TABLE loyalty_redemptions
    ADD COLUMN IF NOT EXISTS product_id INTEGER NULL,
    ADD COLUMN IF NOT EXISTS product_name VARCHAR(150) NULL;
