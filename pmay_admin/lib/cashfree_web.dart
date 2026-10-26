import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Opens the Cashfree checkout as an in-page popup and completes when the popup closes
/// (paid, failed or dismissed). The result is deliberately NOT used: the caller must ask
/// our server for the real payment status afterwards.
///
/// [environment] is "sandbox" (test keys) or "production" - the backend tells us which.
Future<void> openCashfreeCheckout({required String paymentSessionId, required String environment}) async {
  if (!globalContext.hasProperty('Cashfree'.toJS).toDart) {
    throw Exception('Cashfree SDK did not load. Check your internet connection and reload the page.');
  }
  final init = {'mode': environment == 'production' ? 'production' : 'sandbox'}.jsify() as JSObject;
  final cashfree = (globalContext['Cashfree'] as JSFunction).callAsFunction(null, init) as JSObject;
  final opts = {'paymentSessionId': paymentSessionId, 'redirectTarget': '_modal'}.jsify() as JSObject;
  await cashfree.callMethod<JSPromise<JSAny?>>('checkout'.toJS, opts).toDart;
}