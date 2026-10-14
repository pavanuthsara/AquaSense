import 'package:google_sign_in/google_sign_in.dart';

abstract interface class GoogleIdTokenProvider {
  Future<String?> signIn();

  Future<void> signOut();
}

class PluginGoogleIdTokenProvider implements GoogleIdTokenProvider {
  PluginGoogleIdTokenProvider({required String serverClientId})
    : _initialization = GoogleSignIn.instance.initialize(
        serverClientId: serverClientId,
      );

  final Future<void> _initialization;

  @override
  Future<String?> signIn() async {
    await _initialization;
    try {
      final account = await GoogleSignIn.instance.authenticate();
      return account.authentication.idToken;
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) {
        return null;
      }
      rethrow;
    }
  }

  @override
  Future<void> signOut() async {
    await _initialization;
    await GoogleSignIn.instance.signOut();
  }
}
