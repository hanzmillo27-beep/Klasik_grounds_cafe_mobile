import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import 'http_client_native.dart'
    if (dart.library.js_interop) 'http_client_web.dart';
import 'rate_limiter.dart';

const cafeApiBaseUrl = 'https://klasik-grounds-cafe.onrender.com';
const loyaltyPointsPerReward = 10;

class CafeSession {
  const CafeSession({
    required this.userId,
    required this.username,
    required this.role,
    required this.sessionCookie,
  });

  final int? userId;
  final String username;
  final String role;
  final String sessionCookie;
}

class CafeProduct {
  const CafeProduct({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.price,
    required this.isAvailable,
    this.imageUrl,
  });

  final String id;
  final String name;
  final String category;
  final String description;
  final double price;
  final bool isAvailable;
  final String? imageUrl;

  factory CafeProduct.fromMap(Map<String, dynamic> row) => CafeProduct(
    id: '${row['product_id'] ?? row['id'] ?? ''}',
    name: '${row['product_name'] ?? row['name'] ?? 'Untitled item'}',
    category: '${row['category_name'] ?? row['category'] ?? 'Cafe'}',
    description: '${row['description'] ?? 'Prepared fresh at Klasik Grounds.'}',
    price: _number(row['product_price'] ?? row['price']),
    isAvailable:
        (row['can_order'] as bool? ?? true) &&
        (row['is_available'] as bool? ?? row['available'] as bool? ?? true),
    imageUrl: _stringOrNull(
      row['product_image_url'] ?? row['product_image'] ?? row['image_url'],
    ),
  );
}

class InventoryItem {
  const InventoryItem({
    required this.productId,
    required this.name,
    required this.category,
    required this.quantity,
    required this.unit,
  });

  final String productId;
  final String name;
  final String category;
  final double quantity;
  final String unit;

  bool get isLow => quantity <= 0;
}

class CafeOrder {
  const CafeOrder({
    required this.id,
    required this.referenceCode,
    required this.status,
    required this.total,
    required this.createdAt,
    required this.itemCount,
  });

  final String id;
  final String referenceCode;
  final String status;
  final double total;
  final DateTime? createdAt;

  /// Number of distinct sale item lines, as returned by POS transactions.
  final int itemCount;

  factory CafeOrder.fromMap(Map<String, dynamic> row) => CafeOrder(
    id: '${row['sale_id'] ?? ''}',
    referenceCode: '',
    status: 'completed',
    total: _number(row['total_amount']),
    createdAt: _saleDate(row['sale_date']),
    itemCount: _integer(row['item_count']),
  );
}

class MemberProfile {
  const MemberProfile({
    required this.fullName,
    required this.loyaltyPoints,
    this.earningsCount = 0,
    this.redemptionsCount = 0,
    this.activity = const [],
  });

  final String fullName;
  final int loyaltyPoints;
  final int earningsCount;
  final int redemptionsCount;
  final List<LoyaltyActivity> activity;
}

class LoyaltyActivity {
  const LoyaltyActivity({
    required this.title,
    required this.detail,
    required this.createdAt,
    required this.isRedemption,
  });

  final String title;
  final String detail;
  final DateTime createdAt;
  final bool isRedemption;
}

class LoyaltyRedemption {
  const LoyaltyRedemption({
    required this.rewardCode,
    required this.productId,
    required this.productName,
    required this.points,
    required this.pointsSpent,
  });

  final String rewardCode;
  final String productId;
  final String productName;
  final int points;
  final int pointsSpent;
}

/// HTTP client for the Klasik Grounds web API.
class ApiService {
  ApiService({
    http.Client? client,
    RateLimiter? rateLimiter,
    this.baseUrl = cafeApiBaseUrl,
    this.sessionCookie,
  }) : _client = client ?? createHttpClient(),
       _rateLimiter = rateLimiter ?? _sharedRateLimiter;

  static final _sharedRateLimiter = RateLimiter();
  final http.Client _client;
  final RateLimiter _rateLimiter;
  final String baseUrl;
  String? sessionCookie;

  Future<CafeSession> signIn({
    required String username,
    required String password,
  }) async {
    _rateLimiter.check(
      'sign-in attempts',
      limit: 5,
      window: const Duration(minutes: 1),
    );
    // The web login page initializes a PHP session. Reuse that session when
    // posting the credentials instead of starting a fresh session directly.
    final loginPage = await _readLoginPage(Uri.parse(baseUrl).resolve('/Auth'));
    if (loginPage.statusCode < 200 || loginPage.statusCode >= 300) {
      _throwLoginFailure(loginPage);
    }

    final request =
        http.Request('POST', Uri.parse(baseUrl).resolve('/Auth/login'))
          ..followRedirects = kIsWeb
          ..headers['Accept'] = 'text/html,application/json'
          ..bodyFields = {'username': username.trim(), 'password': password};
    if (!kIsWeb && sessionCookie != null && sessionCookie!.isNotEmpty) {
      request.headers['Cookie'] = sessionCookie!;
    }
    late final http.StreamedResponse streamedResponse;
    try {
      streamedResponse = await _client.send(request);
    } on http.ClientException {
      if (kIsWeb) throw StateError(_browserCorsError);
      rethrow;
    }
    final responseUrl = streamedResponse is http.BaseResponseWithUrl
        ? (streamedResponse as http.BaseResponseWithUrl).url
        : null;
    final response = await http.Response.fromStream(streamedResponse);
    _captureSessionCookie(response.headers['set-cookie']);

    if (kIsWeb
        ? response.statusCode < 200 || response.statusCode >= 300
        : response.statusCode < 300 || response.statusCode >= 400) {
      _throwLoginFailure(response);
    }
    final redirect = response.headers['location'];
    final redirectUri = kIsWeb
        ? responseUrl
        : redirect == null || redirect.isEmpty
        ? null
        : Uri.parse(baseUrl).resolve(redirect);
    if (redirectUri != null && !_sameOrigin(redirectUri, Uri.parse(baseUrl))) {
      throw StateError('The sign-in server redirected to a different website.');
    }
    final redirectSegments = (redirectUri?.pathSegments ?? const <String>[])
        .map((segment) => segment.toLowerCase())
        .toList();
    final redirectPath = redirectUri?.path.toLowerCase();
    final finalRedirectSegment = redirectSegments.isEmpty
        ? ''
        : redirectSegments.last;
    if (redirectPath == null) {
      throw StateError('The sign-in response did not include an account page.');
    }
    if (finalRedirectSegment == 'auth' || finalRedirectSegment == 'login') {
      // PHP puts the rejection message in a session flash, then redirects.
      // Read it once with the updated session instead of guessing the cause.
      final resultPage = kIsWeb ? response : await _readLoginPage(redirectUri!);
      if (resultPage.statusCode < 200 || resultPage.statusCode >= 300) {
        _throwLoginFailure(resultPage);
      }
      throw StateError(
        _loginError(resultPage.body) ??
            'The server did not confirm your account access. '
                'Please try again or check your account role.',
      );
    }
    final role = _roleFromRedirect(redirectSegments);
    if (role == null) {
      throw StateError(
        'The website redirected to an unsupported account page.',
      );
    }
    if (!kIsWeb && (sessionCookie == null || sessionCookie!.isEmpty)) {
      throw StateError(
        'The sign-in server did not return a session cookie. Please try again.',
      );
    }
    return CafeSession(
      userId: null,
      username: username.trim(),
      role: role,
      sessionCookie: sessionCookie ?? '',
    );
  }

  Future<http.Response> _readLoginPage(Uri uri) async {
    final headers = <String, String>{'Accept': 'text/html'};
    if (!kIsWeb && sessionCookie != null && sessionCookie!.isNotEmpty) {
      headers['Cookie'] = sessionCookie!;
    }
    late final http.Response response;
    try {
      final request = http.Request('GET', uri)
        ..followRedirects = kIsWeb
        ..headers.addAll(headers);
      response = await http.Response.fromStream(await _client.send(request));
    } on http.ClientException {
      if (kIsWeb) throw StateError(_browserCorsError);
      rethrow;
    }
    _captureSessionCookie(response.headers['set-cookie']);
    return response;
  }

  Never _throwLoginFailure(http.Response response) {
    final message = _loginError(response.body);
    if (response.statusCode == 429) {
      final seconds = int.tryParse(response.headers['retry-after'] ?? '');
      throw RateLimitException(
        action: 'sign-in attempts',
        retryAfter: Duration(
          seconds: seconds != null && seconds > 0 ? seconds : 60,
        ),
        serverMessage: message,
      );
    }
    throw StateError(
      message ??
          'Could not sign in. Please try again. (HTTP ${response.statusCode})',
    );
  }

  Future<List<CafeProduct>> fetchProducts() async {
    final response = await _request('GET', '/api/Kiosk/products');
    return _asList(response)
        .map((row) => CafeProduct.fromMap(_asMap(row)))
        .where((product) => product.id.isNotEmpty)
        .toList();
  }

  Future<List<InventoryItem>> fetchInventory() async {
    final response = await _request('GET', '/api/Inventory/all');
    return _asList(response).map((row) {
      final map = _asMap(row);
      return InventoryItem(
        productId: '${map['inv_id'] ?? map['id'] ?? ''}',
        name: '${map['inv_name'] ?? map['name'] ?? 'Unnamed stock item'}',
        category: '${map['category'] ?? 'Stockroom'}',
        quantity: _number(map['amount'] ?? map['quantity']),
        unit: '${map['unit'] ?? ''}',
      );
    }).toList();
  }

  Future<List<CafeOrder>> fetchRecentOrders() async {
    final response = await _request(
      'GET',
      '/api/POS/transactions',
      unwrapData: false,
    );
    if (response is Map &&
        (response['status'] == 'error' ||
            response['success'] == false ||
            response['error'] != null)) {
      throw StateError(
        _errorMessage(response) ?? 'Could not load recent sales.',
      );
    }
    final rows = response is Map ? response['data'] : null;
    if (rows is! List) {
      throw StateError(
        'The recent sales API returned an invalid transactions list.',
      );
    }
    return rows.map((row) {
      if (row is! Map<String, dynamic> ||
          (row['sale_id'] is! String && row['sale_id'] is! num) ||
          _stringOrNull(row['sale_id']) == null) {
        throw StateError(
          'The recent sales API returned an invalid transaction.',
        );
      }
      return CafeOrder.fromMap(row);
    }).toList();
  }

  Future<MemberProfile> fetchProfile(CafeSession? session) async {
    if (session == null) {
      return const MemberProfile(fullName: 'Guest', loyaltyPoints: 0);
    }
    final response = await _request('GET', '/api/Loyalty/summary');
    final data = _asMap(response);
    final summary = _asMap(data['summary'] ?? data['loyalty'] ?? data);
    final activity = _asList(summary['activity']).map((row) {
      final entry = _asMap(row);
      final code = _stringOrNull(entry['reward_code']);
      final points = _integer(entry['points']);
      return LoyaltyActivity(
        title: '${entry['description'] ?? 'Loyalty activity'}',
        detail:
            '${points > 0 ? '+' : ''}$points points'
            '${code == null ? '' : ' · $code'}',
        createdAt:
            _saleDate(entry['activity_date']) ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        isRedemption: entry['activity_type'] == 'redeemed',
      );
    }).toList();
    return MemberProfile(
      fullName: session.username,
      loyaltyPoints: _integer(
        summary['loyalty_points'] ?? summary['points'] ?? summary['balance'],
      ),
      earningsCount: summary['earnings_count'] == null
          ? activity.where((entry) => !entry.isRedemption).length
          : _integer(summary['earnings_count']),
      redemptionsCount: summary['redemptions_count'] == null
          ? activity.where((entry) => entry.isRedemption).length
          : _integer(summary['redemptions_count']),
      activity: activity,
    );
  }

  Future<String> createKioskOrder({
    required String customerName,
    required int? customerUserId,
    required List<Map<String, dynamic>> items,
  }) async {
    if (items.isEmpty) throw StateError('Add an item before placing an order.');
    if (customerName.trim().isEmpty) {
      throw StateError('Enter a name for this order.');
    }

    _rateLimiter.check(
      'order submissions',
      limit: 1,
      window: const Duration(seconds: 3),
    );

    // app/api/Kiosk/KioskController.php reads $_POST['items'] as a JSON string.
    final fields = <String, String>{
      'customer_name': customerName.trim(),
      'items': jsonEncode(
        items
            .map(
              (item) => {
                'product_id': _integer(item['product_id']),
                'quantity': _integer(item['quantity']),
              },
            )
            .toList(),
      ),
    };
    if (customerUserId != null) {
      fields['customer_user_id'] = customerUserId.toString();
    }

    final response = await _request(
      'POST',
      '/api/Kiosk/submit',
      formFields: fields,
      unwrapData: false,
    );
    final result = _asMap(response);
    final status = result['status'];
    if ((status != null && status != 'success') ||
        result['success'] == false ||
        result['error'] != null) {
      throw StateError(_errorMessage(result) ?? 'The order was rejected.');
    }
    if (status != 'success') {
      throw StateError(
        'The server did not confirm this order. '
        'Check with the cafe before submitting again to avoid a duplicate order.',
      );
    }
    // The cashier looks up this exact server-generated code, not a numeric ID.
    final reference = result['reference_code'];
    if (reference is String && reference.trim().isNotEmpty) {
      return reference.trim();
    }
    throw StateError(
      'The server confirmed this order but did not return its reference. '
      'Check with the cafe before submitting again to avoid a duplicate order.',
    );
  }

  Future<LoyaltyRedemption> redeemLoyalty({required String productId}) async {
    final id = int.tryParse(productId);
    if (id == null || id <= 0) {
      throw StateError('Choose a valid menu item to redeem.');
    }

    // The legacy /redeem route ignores product selection and spends points on
    // a generic coffee voucher. Use the item-aware endpoint exclusively.
    final response = await _request(
      'POST',
      '/api/Loyalty/redeemItem',
      body: {'product_id': id},
      unwrapData: false,
    );
    final result = _asMap(response);
    if (result['status'] == 'error' ||
        result['success'] == false ||
        result['error'] != null) {
      throw StateError(_errorMessage(result) ?? 'The redemption was rejected.');
    }
    final data = _asMap(result['data']);
    final code = _stringOrNull(data['reward_code']);
    final name = _stringOrNull(data['product_name']);
    final remaining = int.tryParse('${data['points']}');
    final cost = int.tryParse('${data['points_spent']}');
    if (result['status'] != 'success' ||
        code == null ||
        name == null ||
        int.tryParse('${data['product_id']}') != id ||
        remaining == null ||
        remaining < 0 ||
        cost != loyaltyPointsPerReward) {
      throw StateError(
        'The server did not return a complete redemption receipt. '
        'Check with the cafe before redeeming again.',
      );
    }
    return LoyaltyRedemption(
      rewardCode: code,
      productId: id.toString(),
      productName: name,
      points: remaining,
      pointsSpent: cost!,
    );
  }

  Future<dynamic> _request(
    String method,
    String path, {
    Object? body,
    Map<String, String>? formFields,
    bool unwrapData = true,
  }) async {
    final uri = Uri.parse(baseUrl).resolve(path);
    final headers = <String, String>{'Accept': 'application/json'};
    if (body != null) headers['Content-Type'] = 'application/json';
    if (!kIsWeb && sessionCookie != null && sessionCookie!.isNotEmpty) {
      headers['Cookie'] = sessionCookie!;
    }
    late final http.Response response;
    final encodedBody = body == null ? null : jsonEncode(body);
    try {
      if (formFields != null) {
        final request = http.MultipartRequest(method, uri)
          ..headers.addAll(headers)
          ..fields.addAll(formFields);
        response = await http.Response.fromStream(await _client.send(request));
      } else {
        switch (method) {
          case 'GET':
            response = await _client.get(uri, headers: headers);
          case 'POST':
            response = await _client.post(
              uri,
              headers: headers,
              body: encodedBody,
            );
          case 'DELETE':
            response = await _client.delete(uri, headers: headers);
          default:
            throw ArgumentError.value(
              method,
              'method',
              'Unsupported HTTP method',
            );
        }
      }
    } on http.ClientException {
      if (kIsWeb) throw StateError(_browserCorsError);
      rethrow;
    }

    dynamic decoded;
    if (response.body.isNotEmpty) {
      try {
        decoded = jsonDecode(response.body);
      } on FormatException {
        decoded = response.body;
      }
    }
    final isHtml = (response.headers['content-type'] ?? '')
        .toLowerCase()
        .contains('text/html');
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (isHtml) {
        if (response.statusCode == 404 && path == '/api/Loyalty/redeemItem') {
          throw StateError(
            'Item rewards are not available at the cafe yet. Please try again later.',
          );
        }
        if (response.statusCode == 401) {
          throw StateError('Please sign in again to continue.');
        }
        if (response.statusCode == 403) {
          throw StateError(
            'Your account does not have permission to perform this action.',
          );
        }
        throw StateError(
          'The cafe service could not complete this request. Please try again later.',
        );
      }
      final message = _errorMessage(decoded) ?? 'HTTP ${response.statusCode}';
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw StateError('API authorization failed at ${uri.path}: $message');
      }
      throw StateError(message);
    }
    if (isHtml) {
      throw StateError(
        'The cafe service returned an unexpected response. Please try again later.',
      );
    }
    _captureSessionCookie(response.headers['set-cookie']);
    if (unwrapData &&
        decoded is Map<String, dynamic> &&
        decoded.containsKey('data')) {
      return decoded['data'];
    }
    return decoded;
  }

  void close() => _client.close();

  void _captureSessionCookie(String? setCookieHeader) {
    if (setCookieHeader == null || setCookieHeader.isEmpty) return;
    // package:http combines repeated Set-Cookie headers with commas. Expires
    // attributes also contain commas, so select the PHP cookie by name.
    final matches = RegExp(
      r'(?:^|,\s*)(PHPSESSID=([^;,\s]*))',
      caseSensitive: false,
    ).allMatches(setCookieHeader);
    if (matches.isNotEmpty) {
      final match = matches.last;
      sessionCookie = match[2]!.isEmpty ? null : match[1];
    }
  }
}

bool _sameOrigin(Uri first, Uri second) =>
    first.scheme == second.scheme &&
    first.host == second.host &&
    first.port == second.port;

String? _loginError(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map) return _errorMessage(decoded);
  } on FormatException {
    // The PHP login renders its flash error inside the HTML form.
  }
  final alert = RegExp(
    r'''<div\b[^>]*\bclass\s*=\s*["'][^"']*\balert-danger\b[^"']*["'][^>]*>([\s\S]*?)</div>''',
    caseSensitive: false,
  ).firstMatch(body);
  if (alert == null) return null;
  final message = _htmlToText(alert[1]!)
      .replaceAll('&quot;', '"')
      .replaceAll('&#039;', "'")
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');
  return _stringOrNull(message);
}

String? _roleFromRedirect(List<String> pathSegments) {
  if (pathSegments.contains('dashboard')) return 'owner';
  if (pathSegments.contains('products')) return 'staff';
  if (pathSegments.contains('users')) return 'admin';
  if (pathSegments.contains('pos')) return 'cashier';
  if (pathSegments.contains('loyalty')) return 'loyal_customer';
  if (pathSegments.contains('kiosk')) return 'user';
  return null;
}

const _browserCorsError =
    'The browser blocked this API request. The Render server must allow this app origin with CORS credentials, and its PHP session cookie must allow cross-site requests.';

List<dynamic> _asList(dynamic value) {
  if (value is List) return value;
  if (value is Map<String, dynamic>) {
    for (final key in ['data', 'items', 'products', 'inventory']) {
      if (value[key] is List) return value[key] as List<dynamic>;
    }
  }
  return const [];
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return const {};
}

String? _errorMessage(dynamic value) {
  if (value is Map) {
    return _stringOrNull(value['message'] ?? value['error'] ?? value['title']);
  }
  return _stringOrNull(value);
}

String? _stringOrNull(dynamic value) {
  if (value == null) return null;
  final result = value.toString().trim();
  return result.isEmpty ? null : result;
}

double _number(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

int _integer(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

DateTime? _saleDate(dynamic value) {
  if (value is! String) return null;
  final timestamp = value.trim();
  final parts = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})'
    r'(?:\.\d+)?([zZ]|[+-]\d{2}(?::?\d{2})?)?$',
  ).firstMatch(timestamp);
  if (parts == null) return null;
  final components = List.generate(6, (index) => int.parse(parts[index + 1]!));
  final calendarDate = DateTime.utc(
    components[0],
    components[1],
    components[2],
    components[3],
    components[4],
    components[5],
  );
  // DateTime.tryParse normalizes invalid calendar values, such as February 30.
  if (calendarDate.year != components[0] ||
      calendarDate.month != components[1] ||
      calendarDate.day != components[2] ||
      calendarDate.hour != components[3] ||
      calendarDate.minute != components[4] ||
      calendarDate.second != components[5]) {
    return null;
  }
  final offset = parts[7];
  if (offset != null && offset != 'Z' && offset != 'z') {
    final digits = offset.substring(1).replaceAll(':', '');
    if (int.parse(digits.substring(0, 2)) > 23 ||
        (digits.length > 2 && int.parse(digits.substring(2)) > 59)) {
      return null;
    }
  }
  // PHP stores sale_date in Asia/Manila without an offset.
  return DateTime.tryParse(offset == null ? '$timestamp+08:00' : timestamp);
}

String _htmlToText(String html) => html
    .replaceAll(RegExp(r'<[^>]*>'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
