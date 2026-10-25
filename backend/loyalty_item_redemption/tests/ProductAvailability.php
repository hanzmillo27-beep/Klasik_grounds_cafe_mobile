<?php
namespace Models;

class ProductAvailability
{
    // Product queries use alias p. An empty recipe represents an untracked product.
    public static function stockSql(): string
    {
        return 'NOT EXISTS (
            SELECT 1 FROM product_ingredients recipe
            LEFT JOIN inventory ingredient ON ingredient.inv_id = recipe.inv_id
            WHERE recipe.product_id = p.product_id AND (
                ingredient.inv_id IS NULL OR ingredient.amount IS NULL OR recipe.quantity_required IS NULL
                OR NOT (recipe.quantity_required >= 0.001 AND recipe.quantity_required <= 999999999.999
                    AND ROUND(recipe.quantity_required, 3) = recipe.quantity_required
                    AND ingredient.amount >= 0 AND ingredient.amount <= 999999999.999
                    AND ROUND(ingredient.amount, 3) = ingredient.amount
                    AND ingredient.amount >= recipe.quantity_required)
            )
        )';
    }

    public static function apply(object $product): void
    {
        foreach (['is_active', 'is_available', 'stock_available'] as $field) {
            $product->$field = in_array($product->$field, [true, 1, '1', 't', 'true'], true);
        }
        $product->can_order = $product->is_active && $product->is_available && $product->stock_available;
        $product->availability_reason = !$product->is_active ? 'Product is inactive.'
            : (!$product->is_available ? 'Manually marked unavailable.'
                : (!$product->stock_available ? 'Insufficient ingredients.' : ''));
    }

    public static function assertStock(\PDO $db, array $items): void
    {
        $quantities = [];
        foreach ($items as $item) $quantities[(int) $item['product_id']] = (int) $item['quantity'];
        if (!$quantities) return;
        $placeholders = implode(',', array_fill(0, count($quantities), '?'));
        $stmt = $db->prepare('SELECT recipe.product_id, recipe.inv_id, recipe.quantity_required,
            ingredient.amount FROM product_ingredients recipe
            LEFT JOIN inventory ingredient ON ingredient.inv_id = recipe.inv_id
            WHERE recipe.product_id IN (' . $placeholders . ') ORDER BY recipe.inv_id, recipe.product_id');
        $stmt->execute(array_keys($quantities));
        $demand = [];
        $stock = [];
        foreach ($stmt->fetchAll() as $ingredient) {
            if (!Inventory::validQuantity($ingredient->quantity_required, false) || !Inventory::validQuantity($ingredient->amount)) {
                throw new \Exception('A product is unavailable. Check its recipe and ingredient stock.');
            }
            $id = (int) $ingredient->inv_id;
            $demand[$id] = ($demand[$id] ?? 0)
                + (int) round((float) $ingredient->quantity_required * 1000) * $quantities[$ingredient->product_id];
            $stock[$id] = (int) round((float) $ingredient->amount * 1000);
        }
        foreach ($demand as $id => $required) {
            if ($stock[$id] < $required) throw new \Exception('A product is unavailable. There are not enough ingredients for this order.');
        }
    }
}
