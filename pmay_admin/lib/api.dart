import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// All admin endpoints are defined here. If your backend routes differ, change them here only.
class Ep {
  static const login = '/auth/login';
  static const stats = '/admin/stats';
  static String list(String q, String stage) =>
      '/admin/applicants?search=${Uri.encodeQueryComponent(q)}&stage=${Uri.encodeQueryComponent(stage)}';
  static String one(String id) => '/admin/applicants/$id';
  static const docSettings = '/admin/document-settings'; // GET -> {settings:[{kind,label,max_size_mb,allowed_extensions,ai_validation}]}
  static String docSettingSave(String kind) => '/admin/document-settings/$kind'; // POST {max_size_mb, ai_validation}
  static const users = '/admin/users'; // GET -> {users:[{user_id,display_name,email,role,assigned_at}]}
  static const userAssign = '/admin/users/assign'; // POST {email, role, search_all, display_name}
  static const userInvite = '/admin/users/invite'; // POST {email, role, display_name}
  static const userCreate = '/admin/users/create'; // POST {email, password, role, display_name, auto_confirm}
  static String userName(String id) => '/admin/users/$id/name'; // POST {display_name}
  static String userDelete(String id) => '/admin/users/$id/delete'; // POST
  static const dbTables = '/admin/db/tables'; // GET -> {tables:[{name,label,count}]}  (auth users table name: auth_users)
  static String dbRows(String t, String q) => '/admin/db/tables/$t?search=${Uri.encodeQueryComponent(q)}'; // GET -> {columns:[..], rows:[{..}]}
  static String dbUpdate(String t, String id) => '/admin/db/tables/$t/$id/update'; // POST {data:{..}}
  static String dbDelete(String t, String id) => '/admin/db/tables/$t/$id/delete'; // POST
  static String setStage(String id) => '/admin/applicants/$id/stage'; // POST {stage}
  static const systemStatus = '/admin/system-status'; // GET -> {status:{database,storage,email,push,ocr:{ok,detail}}}
  static String agreementReview(String id) => '/admin/applicants/$id/agreement-review'; // POST {action: accept|reject, reason}
  static String bankReview(String id) => '/admin/applicants/$id/bank-review'; // POST {action: accept|reject, reason}
  static String review(String id) => '/admin/applicants/$id/review'; // POST {decision, reason}
  static String doc(String id, String kind) => '/admin/applicants/$id/documents/$kind'; // file bytes (image / PDF)
  static const units = '/admin/units'; // GET -> {units:[{id,unit_number,tower,wing,floor,carpet_area,amount,status,allotted_to}]}
  static const eligibleApplicants = '/admin/units/eligible-applicants'; // GET -> {applicants:[{id,unique_id,first_name,last_name}]}
  static String allot(String unitId) => '/admin/units/$unitId/allot'; // POST {applicant_id}
  static String sendContactOtp(String id) => '/admin/applicants/$id/send-otp'; // POST {channel: email|phone}
  static String verifyContactOtp(String id) => '/admin/applicants/$id/verify-otp'; // POST {channel: email|phone, otp}
  static String payments(String status) => '/admin/payments?status=$status';
  static String payReceipt(String id) => '/admin/payments/$id/receipt'; // file bytes (image / PDF) of the uploaded receipt
  static String payAct(String id, String act) => '/admin/payments/$id/$act'; // confirm | reject
}

/// Users with any of these roles may log in to the admin panel (what they can do is limited per role, see Api.can*).
const adminRoles = ['super_admin', 'admin', 'finance', 'allotment_manager', 'auditor'];

class ApiException implements Exception {
  final String message;
  final int? status;
  ApiException(this.message, [this.status]);
  @override
  String toString() => message;
}

class Api {
  Api._();
  static final i = Api._();

  /// Real backend. Override at build time: flutter run -d chrome --dart-define=API_BASE=http://localhost:8080/api
  static const _defaultBase = String.fromEnvironment('API_BASE', defaultValue: 'https://pmay-app.onrender.com/api');
  String base = _defaultBase;
  List<String> roles = [];
  String? token;
  String? email;
  void Function()? onUnauthorized;

  bool get loggedIn => token != null;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    base = p.getString('base') ?? base;
    token = p.getString('token');
    email = p.getString('email');
    roles = p.getStringList('roles') ?? [];
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('base', base);
    if (email != null) await p.setString('email', email!);
    await p.setStringList('roles', roles);
    if (token == null) {
      await p.remove('token');
    } else {
      await p.setString('token', token!);
    }
  }

  Future<void> logout() async {
    token = null;
    await save();
  }

  Map<String, String> get _h => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<Map<String, dynamic>> get(String path) => _send('GET', path);
  Future<Map<String, dynamic>> post(String path, [Map<String, dynamic>? body]) => _send('POST', path, body);

  Future<Map<String, dynamic>> _send(String method, String path, [Map<String, dynamic>? body]) async {
    final uri = Uri.parse('$base$path');
    final r = method == 'GET'
        ? await http.get(uri, headers: _h)
        : await http.post(uri, headers: _h, body: jsonEncode(body ?? {}));
    Map<String, dynamic> j;
    try {
      j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException('Server error (${r.statusCode})', r.statusCode);
    }
    if (r.statusCode == 401 && token != null) onUnauthorized?.call();
    if (r.statusCode >= 400 || j['success'] == false) {
      throw ApiException('${j['error'] ?? 'Something went wrong'}', r.statusCode);
    }
    return j;
  }

  Future<Uint8List> fileBytes(String path) async {
    final r = await http.get(Uri.parse('$base$path'), headers: _h);
    if (r.statusCode >= 400) throw ApiException('Document not found', r.statusCode);
    return r.bodyBytes;
  }
}
/// What the signed-in role may do. The server enforces the same rules; this only hides buttons that would be refused.
extension Perms on Api {
  bool _has(List<String> r) => roles.any(r.contains);
  bool get isSuper => _has(['super_admin']);
  bool get canReview => _has(['super_admin', 'admin']); // validation, agreement, bank review
  bool get canPayments => _has(['super_admin', 'admin', 'finance']);
  bool get canAllot => _has(['super_admin', 'admin', 'allotment_manager']);
}