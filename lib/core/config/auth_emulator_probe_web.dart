import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Whether the web Auth SDK's default instance is pointed at an emulator,
/// or null when that can't be read.
///
/// FlutterFire loads the Firebase JS SDK modules as `window.firebase_core`
/// and `window.firebase_auth`; `getAuth(getApp())` returns the instance the
/// app uses, and its `emulatorConfig` is null when it talks to the real
/// Auth service.
bool? authUsesEmulator() {
  try {
    final core = globalContext.getProperty<JSObject?>('firebase_core'.toJS);
    final auth = globalContext.getProperty<JSObject?>('firebase_auth'.toJS);
    if (core == null || auth == null) return null;
    final app = core.callMethod<JSObject>('getApp'.toJS);
    final instance = auth.callMethod<JSObject>('getAuth'.toJS, app);
    return instance.getProperty<JSAny?>('emulatorConfig'.toJS) != null;
  } catch (_) {
    return null;
  }
}
