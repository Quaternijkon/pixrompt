import 'package:flutter/material.dart';

import '../app/pixrompt_sync_controller.dart';
import '../data/pixrompt_api_client.dart';
import '../domain/sync_models.dart';
import 'pixrompt_design.dart';

Future<void> showAccountSyncSheet(
  BuildContext context, {
  required PixromptSyncController syncController,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (context) => AccountSyncSheet(syncController: syncController),
  );
}

class AccountSyncSheet extends StatefulWidget {
  const AccountSyncSheet({
    super.key,
    required this.syncController,
  });

  final PixromptSyncController syncController;

  @override
  State<AccountSyncSheet> createState() => _AccountSyncSheetState();
}

class _AccountSyncSheetState extends State<AccountSyncSheet> {
  late final TextEditingController _apiBaseUrlController;
  late final TextEditingController _emailController;
  late final TextEditingController _passwordController;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _apiBaseUrlController = TextEditingController(
      text: defaultPixromptApiBaseUrl,
    );
    _emailController = TextEditingController();
    _passwordController = TextEditingController();
    _emailController.addListener(_credentialsChanged);
    _passwordController.addListener(_credentialsChanged);
  }

  @override
  void dispose() {
    _emailController.removeListener(_credentialsChanged);
    _passwordController.removeListener(_credentialsChanged);
    _apiBaseUrlController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _credentialsChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.syncController,
      builder: (context, _) {
        final status = widget.syncController.status;
        final signedIn = status.accountEmail?.isNotEmpty ?? false;
        return PixromptSheetFrame(
          child: Column(
            key: const ValueKey('accountSync.sheet'),
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.cloud_sync_outlined),
                  const SizedBox(width: PixromptSpace.sm),
                  Expanded(
                    child: Text(
                      'Account and Sync',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: PixromptSpace.sm),
              Text(
                'Sign in to sync this library across devices.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: PixromptSpace.lg),
              if (status.isSyncing) ...[
                const LinearProgressIndicator(
                  key: ValueKey('accountSync.progress'),
                  minHeight: 3,
                ),
                const SizedBox(height: PixromptSpace.lg),
              ],
              if (status.message?.isNotEmpty ?? false) ...[
                _StatusMessage(message: status.message!),
                const SizedBox(height: PixromptSpace.lg),
              ],
              if (signedIn)
                _buildSignedInState(context, status)
              else
                _buildSignInForm(context, status.isSyncing),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSignInForm(BuildContext context, bool loading) {
    final canLogin = !loading &&
        _emailController.text.trim().isNotEmpty &&
        _passwordController.text.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          key: const ValueKey('accountSync.apiBaseUrlField'),
          controller: _apiBaseUrlController,
          enabled: !loading,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.url],
          decoration: const InputDecoration(
            labelText: 'API Base URL',
            prefixIcon: Icon(Icons.link),
          ),
        ),
        const SizedBox(height: PixromptSpace.md),
        TextField(
          key: const ValueKey('accountSync.emailField'),
          controller: _emailController,
          enabled: !loading,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.email],
          decoration: const InputDecoration(
            labelText: 'Email',
            prefixIcon: Icon(Icons.alternate_email),
          ),
        ),
        const SizedBox(height: PixromptSpace.md),
        TextField(
          key: const ValueKey('accountSync.passwordField'),
          controller: _passwordController,
          enabled: !loading,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.visiblePassword,
          obscureText: _obscurePassword,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.password],
          onSubmitted: (_) {
            if (canLogin) _submitLogin();
          },
          decoration: InputDecoration(
            labelText: 'Password',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              tooltip: _obscurePassword ? 'Show password' : 'Hide password',
              onPressed: loading
                  ? null
                  : () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
            ),
          ),
        ),
        const SizedBox(height: PixromptSpace.lg),
        FilledButton.icon(
          key: const ValueKey('accountSync.loginButton'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
          onPressed: canLogin ? _submitLogin : null,
          icon: loading
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    semanticsLabel: 'Logging in',
                  ),
                )
              : const Icon(Icons.login),
          label: Text(loading ? 'Logging in' : 'Login'),
        ),
      ],
    );
  }

  Widget _buildSignedInState(BuildContext context, SyncStatus status) {
    final loading = status.isSyncing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: pixromptSurfaceDecoration(
            color: PixromptPalette.darkSurfaceHigh.withOpacity(0.46),
            radius: PixromptRadius.lg,
            elevated: false,
          ),
          child: Padding(
            padding: const EdgeInsets.all(PixromptSpace.lg),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.account_circle_outlined, size: 32),
                const SizedBox(width: PixromptSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Signed in as',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: PixromptSpace.xs),
                      Text(
                        status.accountEmail!,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: PixromptSpace.xs),
                      Text(
                        _lastSyncLabel(status.lastSyncAt),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: PixromptSpace.lg),
        Wrap(
          spacing: PixromptSpace.sm,
          runSpacing: PixromptSpace.sm,
          children: [
            FilledButton.icon(
              key: const ValueKey('accountSync.manualSyncButton'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(48, 48),
              ),
              onPressed: loading ? null : _manualSync,
              icon: loading
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        semanticsLabel: 'Syncing',
                      ),
                    )
                  : const Icon(Icons.sync),
              label: Text(loading ? 'Syncing' : 'Sync Now'),
            ),
            FilledButton.tonalIcon(
              key: const ValueKey('accountSync.logoutButton'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(48, 48),
              ),
              onPressed: loading ? null : _logout,
              icon: const Icon(Icons.logout),
              label: const Text('Logout'),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _submitLogin() async {
    if (widget.syncController.status.isSyncing) return;
    FocusScope.of(context).unfocus();
    try {
      await widget.syncController.login(
        email: _emailController.text,
        password: _passwordController.text,
        apiBaseUrl: _apiBaseUrlController.text,
      );
    } catch (_) {
      // The controller exposes the failure message through status.
    } finally {
      if (!mounted) return;
      _passwordController.clear();
      setState(() {});
    }
  }

  Future<void> _manualSync() async {
    if (widget.syncController.status.isSyncing) return;
    try {
      await widget.syncController.manualSync();
    } catch (_) {
      // The controller exposes the failure message through status.
    }
  }

  Future<void> _logout() async {
    if (widget.syncController.status.isSyncing) return;
    try {
      await widget.syncController.logout();
    } catch (_) {
      // The controller exposes the failure message through status.
    } finally {
      if (!mounted) return;
      _passwordController.clear();
    }
  }
}

class _StatusMessage extends StatelessWidget {
  const _StatusMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: pixromptSurfaceDecoration(
        color: PixromptPalette.darkSurfaceHigh.withOpacity(0.46),
        radius: PixromptRadius.md,
        elevated: false,
      ),
      child: Padding(
        padding: const EdgeInsets.all(PixromptSpace.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, size: 20),
            const SizedBox(width: PixromptSpace.sm),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}

String _lastSyncLabel(int? millisecondsSinceEpoch) {
  if (millisecondsSinceEpoch == null) return 'Last sync: Never';
  final value = DateTime.fromMillisecondsSinceEpoch(millisecondsSinceEpoch);
  return 'Last sync: ${_four(value.year)}-${_two(value.month)}-'
      '${_two(value.day)} ${_two(value.hour)}:${_two(value.minute)}';
}

String _two(int value) => value.toString().padLeft(2, '0');
String _four(int value) => value.toString().padLeft(4, '0');
