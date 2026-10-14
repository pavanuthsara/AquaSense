import 'package:flutter/foundation.dart';

import '../domain/auth_models.dart';
import '../domain/authentication_repository.dart';

enum AuthenticationStatus {
  checkingSession,
  signedOut,
  signingIn,
  signedIn,
  signingOut,
}

enum AuthenticationNoticeType { information, error }

class AuthenticationController extends ChangeNotifier {
  AuthenticationController({required AuthenticationRepository repository})
    : _repository = repository;

  final AuthenticationRepository _repository;

  AuthenticationStatus _status = AuthenticationStatus.checkingSession;
  AuthUser? _user;
  String? _notice;
  AuthenticationNoticeType? _noticeType;
  bool _initialized = false;

  AuthenticationStatus get status => _status;
  AuthUser? get user => _user;
  String? get notice => _notice;
  AuthenticationNoticeType? get noticeType => _noticeType;
  bool get isBusy =>
      _status == AuthenticationStatus.checkingSession ||
      _status == AuthenticationStatus.signingIn ||
      _status == AuthenticationStatus.signingOut;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;

    try {
      final session = await _repository.restoreSession();
      _user = session?.user;
      _status = session == null
          ? AuthenticationStatus.signedOut
          : AuthenticationStatus.signedIn;
    } catch (_) {
      _status = AuthenticationStatus.signedOut;
      _setNotice(
        'Your saved session could not be restored. Please sign in again.',
        AuthenticationNoticeType.error,
      );
    }
    notifyListeners();
  }

  Future<void> signInWithGoogle() async {
    if (isBusy) {
      return;
    }

    _status = AuthenticationStatus.signingIn;
    _user = null;
    _clearNotice(notify: false);
    notifyListeners();

    try {
      final result = await _repository.signInWithGoogle();
      switch (result) {
        case GoogleSignInSuccess(:final session):
          _user = session.user;
          _status = AuthenticationStatus.signedIn;
        case GoogleSignInCancelled():
          _status = AuthenticationStatus.signedOut;
          _setNotice(
            'Google sign-in was cancelled.',
            AuthenticationNoticeType.information,
            notify: false,
          );
      }
    } on AuthenticationException catch (error) {
      _status = AuthenticationStatus.signedOut;
      _setNotice(error.message, AuthenticationNoticeType.error, notify: false);
    } catch (_) {
      _status = AuthenticationStatus.signedOut;
      _setNotice(
        'Could not connect to Google. Check your connection and try again.',
        AuthenticationNoticeType.error,
        notify: false,
      );
    }
    notifyListeners();
  }

  Future<void> signOut() async {
    if (_status != AuthenticationStatus.signedIn) {
      return;
    }

    final previousUser = _user;
    _status = AuthenticationStatus.signingOut;
    _clearNotice(notify: false);
    notifyListeners();

    try {
      await _repository.signOut();
      _user = null;
      _status = AuthenticationStatus.signedOut;
    } catch (_) {
      _user = previousUser;
      _status = AuthenticationStatus.signedIn;
      _setNotice(
        'Could not sign out. Please try again.',
        AuthenticationNoticeType.error,
        notify: false,
      );
    }
    notifyListeners();
  }

  void clearNotice() => _clearNotice();

  void _setNotice(
    String message,
    AuthenticationNoticeType type, {
    bool notify = true,
  }) {
    _notice = message;
    _noticeType = type;
    if (notify) {
      notifyListeners();
    }
  }

  void _clearNotice({bool notify = true}) {
    _notice = null;
    _noticeType = null;
    if (notify) {
      notifyListeners();
    }
  }
}
