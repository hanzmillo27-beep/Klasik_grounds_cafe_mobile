import 'dart:async';

import 'package:flutter/material.dart';

import '../controller/auth_controller.dart';
import '../services/api_service.dart';
import '../services/rate_limiter.dart';
import '../theme.dart';
import '../widgets/cafe_logo.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({
    super.key,
    required this.onSignedIn,
    required this.onContinueAsGuest,
  });

  final ValueChanged<CafeSession> onSignedIn;
  final VoidCallback onContinueAsGuest;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  late final _apiService = ApiService();
  late final _authController = AuthController(_apiService);
  bool _busy = false;
  bool _hidePassword = true;
  String? _error;
  Timer? _cooldownTimer;
  int _cooldownSeconds = 0;

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _usernameController.dispose();
    _passwordController.dispose();
    _apiService.close();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || _cooldownSeconds > 0) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = await _authController.signIn(
        _usernameController.text,
        _passwordController.text,
      );
      if (mounted) widget.onSignedIn(session);
    } on RateLimitException catch (error) {
      if (!mounted) return;
      _startCooldown(error);
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error = error is StateError
            ? error.message.toString()
            : error.toString().replaceFirst('Exception: ', ''),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _startCooldown(RateLimitException error) {
    _cooldownTimer?.cancel();
    final seconds = error.retryAfterSeconds;
    setState(() {
      _error = error.message;
      _cooldownSeconds = seconds;
    });
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final remaining = seconds - timer.tick;
      setState(() {
        _cooldownSeconds = remaining > 0 ? remaining : 0;
        if (_cooldownSeconds == 0) _error = null;
      });
      if (_cooldownSeconds == 0) {
        timer.cancel();
        _cooldownTimer = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1040),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth > 760;
                final form = _loginCard(context);
                if (!wide) {
                  return Column(
                    children: [
                      const _BrandHeader(),
                      const SizedBox(height: 22),
                      form,
                    ],
                  );
                }
                return Row(
                  children: [
                    const Expanded(child: _WelcomePanel()),
                    const SizedBox(width: 30),
                    Expanded(child: form),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _loginCard(BuildContext context) => Card(
    elevation: 0,
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(26),
      side: const BorderSide(color: Color(0xFFECEDE7)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(30),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Sign In?',
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(fontSize: 27),
            ),
            const SizedBox(height: 8),
            const SizedBox(height: 25),
            TextFormField(
              controller: _usernameController,
              textInputAction: TextInputAction.next,
              autocorrect: false,
              autofillHints: const [AutofillHints.username],
              decoration: const InputDecoration(
                labelText: 'Username',
                prefixIcon: Icon(Icons.person_outline),
              ),
              validator: (value) => (value?.trim().isEmpty ?? true)
                  ? 'Enter your username.'
                  : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _passwordController,
              obscureText: _hidePassword,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.visiblePassword,
              autofillHints: const [AutofillHints.password],
              onFieldSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  tooltip: _hidePassword ? 'Show password' : 'Hide password',
                  onPressed: () =>
                      setState(() => _hidePassword = !_hidePassword),
                  icon: Icon(
                    _hidePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
              validator: (value) =>
                  (value?.isEmpty ?? true) ? 'Enter your password.' : null,
            ),
            if (_error != null) ...[
              const SizedBox(height: 15),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF0EB),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(
                    color: Color(0xFF9F4326),
                    fontSize: 13,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _busy || _cooldownSeconds > 0 ? null : _submit,
                child: _busy
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        _cooldownSeconds > 0
                            ? 'Try again in ${_cooldownSeconds}s'
                            : 'Sign in',
                      ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : widget.onContinueAsGuest,
                icon: const Icon(Icons.shopping_bag_outlined),
                label: const Text('Start an Order'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _WelcomePanel extends StatelessWidget {
  const _WelcomePanel();

  @override
  Widget build(BuildContext context) => Container(
    height: 570,
    padding: const EdgeInsets.all(40),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(30),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF284A3A), Color(0xFF1D352A)],
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _BrandHeader(light: true),
        const Spacer(),
        const Text(
          'GOOD COFFEE, GOOD COMPANY',
          style: TextStyle(
            fontSize: 10,
            letterSpacing: 1.7,
            color: Color(0xFFE9C5A4),
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'A little pause.\nA lot of heart.',
          style: TextStyle(
            fontSize: 46,
            height: 1.12,
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Browse the menu, place a kiosk order, and keep your cafe visits in one place.',
          style: TextStyle(
            fontSize: 15,
            height: 1.6,
            color: Colors.white.withValues(alpha: .74),
          ),
        ),
        const Spacer(),
        const Icon(Icons.coffee_rounded, size: 42, color: Color(0xFFFFDAB9)),
      ],
    ),
  );
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader({this.light = false});
  final bool light;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const CafeLogo(size: 41),
      const SizedBox(width: 10),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'KLASIK GROUNDS',
            style: TextStyle(
              color: light ? Colors.white : forest,
              fontWeight: FontWeight.w800,
              letterSpacing: .9,
              fontSize: 12,
            ),
          ),
          Text(
            'CAFE  ·  ALL DAY, YOUR WAY',
            style: TextStyle(
              color: light ? Colors.white70 : mutedInk,
              letterSpacing: .8,
              fontSize: 8,
            ),
          ),
        ],
      ),
    ],
  );
}
