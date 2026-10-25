import 'package:http/browser_client.dart';

BrowserClient createHttpClient() => BrowserClient()..withCredentials = true;
