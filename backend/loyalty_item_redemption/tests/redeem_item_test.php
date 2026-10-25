<?php
// Self-contained SQLite checks; never connects to the configured cafe database.
namespace Core {
    class Database {
        public static \PDO $connection;
        public static function connect() { return self::$connection; }
    }
    class BaseController {
        public array $response = [];
        public function json($data): void { $this->response = $data; }
    }
    class Auth {
        public static function requireRole(array $roles): void {
            if (!in_array(self::user()['role'], $roles, true)) {
                throw new \RuntimeException('Forbidden');
            }
        }
        public static function user(): array {
            return ['id' => 1, 'role' => 'loyal_customer'];
        }
    }
}
namespace {
    if (PHP_SAPI !== 'cli') { http_response_code(404); exit; }
    require __DIR__ . '/Model.php';
    require __DIR__ . '/ProductAvailability.php';
    require dirname(__DIR__) . '/app/Models/Loyalty.php';
    require dirname(__DIR__) . '/app/api/Loyalty/LoyaltyController.php';

    function check(bool $condition, string $message): void {
        if (!$condition) throw new \RuntimeException($message);
    }
    function balance(\PDO $db): int {
        return (int) $db->query('SELECT loyalty_points FROM loyal WHERE user_id = 1')->fetchColumn();
    }
    function redemptionCount(\PDO $db): int {
        return (int) $db->query('SELECT COUNT(*) FROM loyalty_redemptions')->fetchColumn();
    }
    function rejected(callable $operation, \PDO $db, string $reason): void {
        $before = [balance($db), redemptionCount($db)];
        $failed = false;
        try { $operation(); }
        catch (\Throwable $error) { $failed = true; }
        check($failed && !$db->inTransaction(), $reason . ': request must fail and close its transaction.');
        check($before === [balance($db), redemptionCount($db)], $reason . ': points and rewards must remain unchanged.');
    }

    $db = new \PDO('sqlite::memory:', null, null, [
        \PDO::ATTR_ERRMODE => \PDO::ERRMODE_EXCEPTION,
        \PDO::ATTR_DEFAULT_FETCH_MODE => \PDO::FETCH_OBJ
    ]);
    \Core\Database::$connection = $db;
    $db->exec('CREATE TABLE loyal (loyalty_id INTEGER PRIMARY KEY, user_id INTEGER UNIQUE, loyalty_points INTEGER NOT NULL)');
    $db->exec('CREATE TABLE products (product_id INTEGER PRIMARY KEY, product_name VARCHAR(150), is_active INTEGER, is_available INTEGER)');
    $db->exec('CREATE TABLE inventory (inv_id INTEGER PRIMARY KEY, amount NUMERIC)');
    $db->exec('CREATE TABLE product_ingredients (product_id INTEGER, inv_id INTEGER, quantity_required NUMERIC)');
    $db->exec('CREATE TABLE loyalty_earnings (user_id INTEGER, earned_at TEXT)');
    $db->exec('CREATE TABLE loyalty_redemptions (
        loyalty_redemption_id INTEGER PRIMARY KEY, user_id INTEGER NOT NULL,
        reward_code TEXT NOT NULL UNIQUE, points_spent INTEGER NOT NULL,
        product_id INTEGER NULL, product_name VARCHAR(150) NULL,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    )');
    $db->exec('INSERT INTO loyal VALUES (1, 1, 25)');
    $db->exec("INSERT INTO products VALUES (1, 'Chocolate cookie', 1, 1), (2, 'Latte', 1, 1),
        (3, 'Unavailable', 1, 0), (4, 'Inactive', 0, 1)");
    $db->exec('INSERT INTO inventory VALUES (1, 0.5)');
    $db->exec('INSERT INTO product_ingredients VALUES (2, 1, 1)');
    $loyalty = new \Models\Loyalty();

    $result = $loyalty->redeemItem(1, 1);
    check($result['points'] === 15 && $result['points_spent'] === 10
        && $result['product_id'] === 1 && $result['product_name'] === 'Chocolate cookie'
        && preg_match('/^GC-[A-F0-9]{8}$/', $result['reward_code']) === 1,
        'A non-coffee item must cost exactly 10 points and return its catalog identity and reward code.');
    $saved = $db->query('SELECT * FROM loyalty_redemptions')->fetch();
    check((int) $saved->product_id === 1 && $saved->product_name === 'Chocolate cookie'
        && $saved->reward_code === $result['reward_code'] && balance($db) === 15,
        'The chosen item, generated code, and points deduction must be persisted together.');
    foreach ([0, -1, 999, 2, 3, 4] as $id) {
        rejected(fn() => $loyalty->redeemItem(1, $id), $db, 'Invalid or unavailable product ' . $id);
    }
    rejected(fn() => $loyalty->redeemItem(99, 1), $db, 'Missing loyalty account');
    $db->exec('UPDATE inventory SET amount = 1 WHERE inv_id = 1');
    $second = $loyalty->redeemItem(1, 2);
    check($second['points'] === 5 && $second['reward_code'] !== $result['reward_code']
        && redemptionCount($db) === 2, 'Another 10 points must allow another chosen item and unique code.');
    check((float) $db->query('SELECT amount FROM inventory WHERE inv_id = 1')->fetchColumn() === 1.0,
        'A reward voucher validates stock without reserving or consuming ingredients.');
    rejected(fn() => $loyalty->redeemItem(1, 1), $db, 'Balance below 10');

    $db->exec('UPDATE loyal SET loyalty_points = 10 WHERE user_id = 1');
    $db->exec("CREATE TRIGGER reject_reward BEFORE INSERT ON loyalty_redemptions BEGIN SELECT RAISE(ABORT, 'test failure'); END");
    rejected(fn() => $loyalty->redeemItem(1, 1), $db, 'Reward insert failure after balance update');
    $db->exec('DROP TRIGGER reject_reward');
    $db->exec('CREATE TRIGGER ignore_balance BEFORE UPDATE ON loyal BEGIN SELECT RAISE(IGNORE); END');
    rejected(fn() => $loyalty->redeemItem(1, 1), $db, 'Guarded balance update failure');
    $db->exec('DROP TRIGGER ignore_balance');
    $db->exec("UPDATE products SET product_name = 'Renamed product' WHERE product_id = 1");
    $db->exec("INSERT INTO loyalty_redemptions (user_id, reward_code, points_spent) VALUES (1, 'GC-LEGACY01', 10)");
    $summary = $loyalty->summary(1);
    $titles = array_map(fn($activity) => $activity->description, $summary['activity']);
    check(in_array('Chocolate cookie', $titles, true) && in_array('Free coffee reward', $titles, true)
        && !in_array('Renamed product', $titles, true),
        'Activity must preserve selected item names and retain legacy reward compatibility.');

    // Supply php://input without changing the production controller or starting
    // a network server. Other php streams are not used by these CLI checks.
    class TestJsonInput {
        public $context;
        public static string $body = '';
        private int $position = 0;
        public function stream_open($path, $mode, $options, &$openedPath): bool { return true; }
        public function stream_read($count): string {
            $chunk = substr(self::$body, $this->position, $count);
            $this->position += strlen($chunk);
            return $chunk;
        }
        public function stream_eof(): bool { return $this->position >= strlen(self::$body); }
        public function stream_stat(): array { return []; }
    }
    stream_wrapper_unregister('php');
    stream_wrapper_register('php', TestJsonInput::class);
    function requestItem(string $body, string $method = 'POST'): array {
        \TestJsonInput::$body = $body;
        $_SERVER['REQUEST_METHOD'] = $method;
        http_response_code(200);
        $controller = new \Api\Loyalty\LoyaltyController();
        $controller->redeemItem();
        return [http_response_code(), $controller->response];
    }
    foreach (['', '{', 'null', '[]', '{}', '{"product_id":0}', '{"product_id":"1"}',
        '{"product_id":1.5}', '{"product_id":true}', '{"product_id":[1]}'] as $body) {
        $before = [balance($db), redemptionCount($db)];
        [$status, $response] = requestItem($body);
        check($status === 400 && $response['status'] === 'error' && !empty($response['message'])
            && $before === [balance($db), redemptionCount($db)], 'Malformed JSON or an invalid item must never spend points.');
    }
    [$status, $response] = requestItem('{"product_id":1}', 'GET');
    check($status === 405 && $response['status'] === 'error', 'Only POST may redeem an item.');
    [$status, $response] = requestItem('{"product_id":1,"product_name":"Forged name","points_spent":0}');
    check($status === 200 && $response['status'] === 'success' && $response['data']['points'] === 0
        && $response['data']['points_spent'] === 10 && $response['data']['product_name'] === 'Renamed product',
        'The JSON endpoint must ignore forged item names and costs and return the authoritative result.');
    stream_wrapper_restore('php');
    echo "Item redemption passed: chosen items, 10-point costs, availability, rollback, history snapshots, and JSON validation.\n";
}
