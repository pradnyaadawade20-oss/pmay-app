import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// Flutter web has no file paths, so picked files are kept in memory and
/// referenced by a pseudo path: web://<id>/<filename>
class WebFiles {
  static final _bytes = <String, Uint8List>{};
  static int _n = 0;
  static String put(String name, Uint8List data) {
    final id = 'web://${_n++}/$name';
    _bytes[id] = data;
    return id;
  }

  static bool isWeb(String p) => p.startsWith('web://');
  static Uint8List? get(String p) => _bytes[p];
}

/// Demo mode (no backend needed):  flutter run -d chrome --dart-define=MOCK=true
/// Fake responses so the UI flow can be previewed. OTP is always 123456.
const bool kMock = bool.fromEnvironment('MOCK');

class _Mock {
  static final Map<String, dynamic> applicant = {
    'first_name': 'Demo',
    'last_name': 'User',
    'unique_id': 'PMAY-00414',
    'email': 'demo@example.com',
    'phone': '+919999999999',
    'registration_stage': 'stage_1_registered',
    'email_verified': false,
    'phone_verified': false,
  };

  static final List<Map<String, dynamic>> payments = [];
  static const _stages = [
    'stage_1_registered', 'stage_3_payment', 'stage_4_allotment', 'stage_5_agreement',
    'stage_6_agreement_receipt', 'stage_7_bank_document', 'stage_8_bank_loan', 'stage_9_mortgage', 'stage_10_completed',
  ];
  static const project = {
    'total_cost': 2550000,
    'booking_amount': 25000,
    'bank_name': 'Yes Bank Ltd',
    'bank_branch': 'Kalyan Branch',
    'bank_account_name': 'Priyanka Home Realtors Pvt Ltd',
  };

  static Map<String, dynamic> handle(String method, String path, [Map<String, dynamic>? body]) {
    if (path == '/mock/advance') {
      final i = _stages.indexOf('${applicant['registration_stage']}');
      applicant['registration_stage'] = _stages[(i + 1) % _stages.length];
      if (applicant['registration_stage'] != 'stage_3_payment') payments.clear();
      return {'success': true};
    }
    if (path == '/payments/offline') {
      payments.add({'payment_status': 'pending', 'amount': body?['amount']});
      return {'success': true};
    }
    if (path == '/me/notifications') {
      final st = '${applicant['registration_stage']}';
      return {
        'success': true,
        'unread': 1,
        'notifications': [
          {'id': 'mock-$st', 'kind': 'stage_changed', 'title': 'Application updated', 'body': 'Your application is now at: $st', 'read_at': null, 'created_at': DateTime.now().toIso8601String()}
        ]
      };
    }
    if (path == '/payments/order') throw ApiException('Demo mode: online payment is not available');
    if (path == '/public/admins') return {'success': true, 'admins': []};
    if (path == '/auth/register') {
      applicant.addAll({
        if ((body?['email'] ?? '') != '') 'email': body!['email'],
        if ((body?['phone'] ?? '') != '') 'phone': body!['phone'],
        if ((body?['firstName'] ?? '') != '') 'first_name': body!['firstName'],
        if ((body?['lastName'] ?? '') != '') 'last_name': body!['lastName'],
      });
      return {'success': true, 'token': 'mock-token', 'roles': []};
    }
    if (path == '/me') return {'success': true, 'applicant': applicant, 'roles': [], 'payments': payments, 'project': project};
    if (path == '/otp/send') return {'success': true, 'devOtp': '123456'};
    if (path == '/otp/verify') {
      if (body?['otp'] != '123456') throw ApiException('Invalid OTP (demo OTP is 123456)', 400);
      applicant[body?['type'] == 'email' ? 'email_verified' : 'phone_verified'] = true;
      return {'success': true};
    }
    throw ApiException('Demo mode: $path not available');
  }
}

class ApiException implements Exception {
  final String message;
  final int? status;
  ApiException(this.message, [this.status]);
  @override
  String toString() => message;
}

/// Thin HTTP client for the Go backend.
/// Android emulator -> host machine is 10.0.2.2. Override with:
///   flutter run --dart-define=API_BASE=https://api.yourdomain.com/api
class Api {
  // Default = live Render API. Override for local dev with --dart-define=API_BASE=http://10.0.2.2:8080/api
  static const _envBase = String.fromEnvironment('API_BASE');
  static String get base => _envBase.isNotEmpty
      ? _envBase
      : 'https://pmay-app.onrender.com/api';
  final _storage = const FlutterSecureStorage();
  String? token;
  void Function()? onUnauthorized;

  Future<void> loadToken() async => token = await _storage.read(key: 'token');
  Future<void> saveToken(String? t) async {
    token = t;
    if (t == null) {
      await _storage.delete(key: 'token');
    } else {
      await _storage.write(key: 'token', value: t);
    }
  }

  Map<String, String> get _auth => {if (token != null) 'Authorization': 'Bearer $token'};

  Map<String, dynamic> _handle(http.Response r) {
    Map<String, dynamic> body;
    try {
      body = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException('Server error (${r.statusCode})', r.statusCode);
    }
    if (r.statusCode == 401 && token != null) onUnauthorized?.call();
    if (r.statusCode >= 400 || body['success'] == false) {
      throw ApiException((body['error'] ?? 'Something went wrong').toString(), r.statusCode);
    }
    return body;
  }

  Future<Map<String, dynamic>> get(String path) async => kMock
      ? _Mock.handle('GET', path)
      : _handle(await http.get(Uri.parse('$base$path'), headers: _auth));

  Future<Map<String, dynamic>> postJson(String path, Map<String, dynamic> body) async => kMock
      ? _Mock.handle('POST', path, body)
      : _handle(await http.post(Uri.parse('$base$path'),
          headers: {..._auth, 'Content-Type': 'application/json'}, body: jsonEncode(body)));

  /// fields: text fields, files: {formFieldName: localFilePath}
  Future<Map<String, dynamic>> postMultipart(String path,
      {Map<String, String> fields = const {}, Map<String, String> files = const {}}) async {
    if (kMock) return _Mock.handle('POST', path, fields);
    final req = http.MultipartRequest('POST', Uri.parse('$base$path'))
      ..headers.addAll(_auth)
      ..fields.addAll(fields);
    for (final e in files.entries) {
      if (WebFiles.isWeb(e.value)) {
        final bytes = WebFiles.get(e.value)!;
        req.files.add(http.MultipartFile.fromBytes(e.key, bytes, filename: e.value.split('/').last));
      } else {
        req.files.add(await http.MultipartFile.fromPath(e.key, e.value));
      }
    }
    final streamed = await req.send().timeout(const Duration(minutes: 3));
    return _handle(await http.Response.fromStream(streamed));
  }

  /// Download a protected file (uploaded document) as bytes.
  Future<List<int>> fileBytes(String relPath) async {
    final r = await http.get(Uri.parse('$base/files/$relPath'), headers: _auth);
    if (r.statusCode >= 400) throw ApiException('Could not load file', r.statusCode);
    return r.bodyBytes;
  }
} 