<?php

namespace Api\Loyalty;

use Core\Auth;
use Core\BaseController;
use Models\Loyalty;

class LoyaltyController extends BaseController
{
    private $Loyalty;

    public function __construct()
    {
        $this->Loyalty = new Loyalty();
    }

    private function customerId(): int
    {
        Auth::requireRole(['loyal_customer']);
        return (int) (Auth::user()['id'] ?? 0);
    }

    public function summary(): void
    {
        $this->json([
            'status' => 'success',
            'data' => $this->Loyalty->summary($this->customerId())
        ]);
    }

    public function redeem(): void
    {
        if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') {
            http_response_code(405);
            $this->json([
                'status' => 'error',
                'message' => 'Use POST to redeem a reward.'
            ]);
        }

        try {
            $result = $this->Loyalty->redeem($this->customerId());
            $this->json([
                'status' => 'success',
                'message' => 'Free coffee redeemed. Show the reward code to the cashier.',
                'data' => $result
            ]);
        } catch (\Throwable $e) {
            http_response_code(400);
            $this->json([
                'status' => 'error',
                'message' => $e->getMessage()
            ]);
        }
    }

    public function redeemItem(): void
    {
        if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') {
            http_response_code(405);
            $this->json([
                'status' => 'error',
                'message' => 'Use POST to redeem an item.'
            ]);
            return;
        }

        try {
            $userId = $this->customerId();
            $input = json_decode(file_get_contents('php://input'), true, 512, JSON_THROW_ON_ERROR);
            if (!is_array($input) || !array_key_exists('product_id', $input)) {
                throw new \InvalidArgumentException('Choose an item to redeem.');
            }
            $productId = $input['product_id'];
            if (!is_int($productId) || $productId < 1) {
                throw new \InvalidArgumentException('Choose a valid item to redeem.');
            }

            $result = $this->Loyalty->redeemItem($userId, $productId);
            $this->json([
                'status' => 'success',
                'message' => 'Item redeemed. Show the reward code to the cashier.',
                'data' => $result
            ]);
        } catch (\JsonException $e) {
            http_response_code(400);
            $this->json([
                'status' => 'error',
                'message' => 'Send a JSON object with the item to redeem.'
            ]);
        } catch (\Throwable $e) {
            http_response_code(400);
            $this->json([
                'status' => 'error',
                'message' => $e->getMessage()
            ]);
        }
    }
}
