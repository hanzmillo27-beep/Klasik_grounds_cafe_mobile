import '../services/api_service.dart';

class AuthController {
  AuthController(this._service);

  final ApiService _service;

  Future<CafeSession> signIn(String username, String password) =>
      _service.signIn(username: username.trim(), password: password);
}
