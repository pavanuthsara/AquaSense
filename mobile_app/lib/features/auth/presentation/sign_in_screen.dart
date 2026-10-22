import 'package:flutter/material.dart';

import '../../../app/config/app_environment.dart';
import 'authentication_controller.dart';
import 'authentication_scope.dart';

class SignInScreen extends StatelessWidget {
  const SignInScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AuthenticationScope.of(context);
    final theme = Theme.of(context);
    final environment = AppEnvironmentScope.of(context);
    final isSigningIn = controller.status == AuthenticationStatus.signingIn;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    child: Container(
                      width: 86,
                      height: 86,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: Icon(
                        Icons.water_rounded,
                        size: 46,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'Welcome to AquaSense',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Sign in to manage your aquariums, workers, tanks, and '
                    'feeding activity.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                  if (!environment.usesRealAuthentication) ...[
                    const SizedBox(height: 24),
                    const _DevelopmentModeNotice(),
                  ],
                  if (controller.notice != null) ...[
                    const SizedBox(height: 16),
                    _AuthenticationNotice(
                      message: controller.notice!,
                      type:
                          controller.noticeType ??
                          AuthenticationNoticeType.information,
                      onDismiss: controller.clearNotice,
                    ),
                  ],
                  const SizedBox(height: 28),
                  if (environment.hasGoogleSignIn ||
                      !environment.usesRealAuthentication)
                    Semantics(
                      button: true,
                      label: 'Continue with Google',
                      child: OutlinedButton(
                        onPressed: isSigningIn
                            ? null
                            : controller.signInWithGoogle,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(56),
                          side: BorderSide(color: theme.colorScheme.outline),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: isSigningIn
                            ? const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                    ),
                                  ),
                                  SizedBox(width: 12),
                                  Text('Connecting securely…'),
                                ],
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _GoogleMark(),
                                  SizedBox(width: 12),
                                  Text('Continue with Google'),
                                ],
                              ),
                      ),
                    ),
                  if (environment.usesRealAuthentication) ...[
                    if (environment.hasGoogleSignIn) ...[
                      const SizedBox(height: 20),
                      const Row(
                        children: [
                          Expanded(child: Divider()),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            child: Text('or use email'),
                          ),
                          Expanded(child: Divider()),
                        ],
                      ),
                      const SizedBox(height: 20),
                    ],
                    _EmailAuthenticationForm(controller: controller),
                  ],
                  const SizedBox(height: 20),
                  Text(
                    'By continuing, you agree to use AquaSense responsibly '
                    'and keep feeding decisions under human supervision.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmailAuthenticationForm extends StatefulWidget {
  const _EmailAuthenticationForm({required this.controller});

  final AuthenticationController controller;

  @override
  State<_EmailAuthenticationForm> createState() =>
      _EmailAuthenticationFormState();
}

class _EmailAuthenticationFormState extends State<_EmailAuthenticationForm> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _creatingAccount = false;
  bool _showPassword = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (widget.controller.isBusy || !_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    if (_creatingAccount) {
      await widget.controller.createAccount(
        email: _email.text.trim(),
        displayName: _name.text.trim(),
        password: _password.text,
      );
    } else {
      await widget.controller.signInWithEmail(
        email: _email.text.trim(),
        password: _password.text,
      );
    }
    if (mounted && widget.controller.notice != null) {
      final position = Scrollable.maybeOf(context)?.position;
      position?.animateTo(
        position.minScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = widget.controller.isBusy;
    return AutofillGroup(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _creatingAccount
                  ? 'Create an account with email'
                  : 'Sign in with email',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            if (_creatingAccount) ...[
              TextFormField(
                controller: _name,
                enabled: !busy,
                decoration: const InputDecoration(
                  labelText: 'Full name',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                autofillHints: const [AutofillHints.name],
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter your name.'
                    : value.trim().length > 255
                    ? 'Use at most 255 characters.'
                    : null,
              ),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _email,
              enabled: !busy,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.email_outlined),
              ),
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [
                AutofillHints.username,
                AutofillHints.email,
              ],
              autocorrect: false,
              validator: (value) {
                final email = value?.trim() ?? '';
                return email.length > 320 ||
                        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)
                    ? 'Enter a valid email address.'
                    : null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _password,
              enabled: !busy,
              obscureText: !_showPassword,
              autocorrect: false,
              enableSuggestions: false,
              autofillHints: [
                _creatingAccount
                    ? AutofillHints.newPassword
                    : AutofillHints.password,
              ],
              textInputAction: _creatingAccount
                  ? TextInputAction.next
                  : TextInputAction.done,
              onFieldSubmitted: (_) {
                if (!_creatingAccount) _submit();
              },
              decoration: InputDecoration(
                labelText: 'Password',
                helperText: _creatingAccount ? 'Use 12–128 characters.' : null,
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  tooltip: _showPassword ? 'Hide password' : 'Show password',
                  onPressed: busy
                      ? null
                      : () => setState(() => _showPassword = !_showPassword),
                  icon: Icon(
                    _showPassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                ),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Enter your password.';
                }
                if (_creatingAccount && value.length < 12) {
                  return 'Use at least 12 characters.';
                }
                if (value.length > 128) return 'Use at most 128 characters.';
                return null;
              },
            ),
            if (_creatingAccount) ...[
              const SizedBox(height: 16),
              TextFormField(
                controller: _confirmation,
                enabled: !busy,
                obscureText: !_showPassword,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'Confirm password',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                validator: (value) => value == null || value.isEmpty
                    ? 'Confirm your password.'
                    : value != _password.text
                    ? 'Passwords do not match.'
                    : null,
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: busy ? null : _submit,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              child: Text(
                busy
                    ? 'Please wait…'
                    : _creatingAccount
                    ? 'Create account'
                    : 'Sign in',
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: busy
                  ? null
                  : () {
                      widget.controller.clearNotice();
                      _formKey.currentState!.reset();
                      _password.clear();
                      _confirmation.clear();
                      setState(() {
                        _creatingAccount = !_creatingAccount;
                        _showPassword = false;
                      });
                    },
              child: Text(
                _creatingAccount
                    ? 'Already have an account? Sign in'
                    : 'New to AquaSense? Create account',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        shape: BoxShape.circle,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: const Text(
        'G',
        style: TextStyle(
          color: Color(0xFF4285F4),
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _DevelopmentModeNotice extends StatelessWidget {
  const _DevelopmentModeNotice();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.science_outlined,
            size: 20,
            color: colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Development mode uses a local test account. No Google account '
              'data is requested yet.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSecondaryContainer,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthenticationNotice extends StatelessWidget {
  const _AuthenticationNotice({
    required this.message,
    required this.type,
    required this.onDismiss,
  });

  final String message;
  final AuthenticationNoticeType type;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isError = type == AuthenticationNoticeType.error;
    final background = isError
        ? colorScheme.errorContainer
        : colorScheme.tertiaryContainer;
    final foreground = isError
        ? colorScheme.onErrorContainer
        : colorScheme.onTertiaryContainer;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            isError ? Icons.error_outline_rounded : Icons.info_outline_rounded,
            color: foreground,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: foreground),
            ),
          ),
          IconButton(
            tooltip: 'Dismiss message',
            onPressed: onDismiss,
            icon: Icon(Icons.close_rounded, color: foreground, size: 20),
          ),
        ],
      ),
    );
  }
}
