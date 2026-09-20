import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/user_state.dart';
import '../utils/app_theme.dart';
import '../utils/ui.dart';

/// First screen. There is still no login in the real sense — no password, no
/// token. "Continue" just looks an existing username up so testing across two
/// devices does not mean creating a new user every time.
enum _Mode { create, continueAs }

class UserScreen extends StatefulWidget {
  const UserScreen({super.key});

  @override
  State<UserScreen> createState() => _UserScreenState();
}

class _UserScreenState extends State<UserScreen> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();
  _Mode _mode = _Mode.create;
  bool _saving = false;

  bool get _isCreate => _mode == _Mode.create;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    final userState = context.read<UserState>();
    final name = _controller.text.trim();
    try {
      if (_isCreate) {
        await userState.createUser(name);
      } else {
        await userState.signInAs(name);
      }
      // main.dart swaps to the home screen as soon as a user exists.
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Brand header
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: AppTheme.violet,
                          borderRadius: BorderRadius.circular(AppTheme.radius),
                        ),
                        child: const Icon(Icons.restaurant_menu,
                            color: Colors.white, size: 32),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'InMinutes',
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        fontStyle: FontStyle.italic,
                        color: AppTheme.textDark,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Order on your own, or share a cart with friends in real time.',
                      style: TextStyle(color: AppTheme.textMuted, height: 1.4),
                    ),
                    const SizedBox(height: 28),

                    // New user / existing user
                    SegmentedButton<_Mode>(
                      segments: const [
                        ButtonSegment(
                          value: _Mode.create,
                          label: Text('New user'),
                          icon: Icon(Icons.person_add_alt, size: 18),
                        ),
                        ButtonSegment(
                          value: _Mode.continueAs,
                          label: Text('I have one'),
                          icon: Icon(Icons.login, size: 18),
                        ),
                      ],
                      selected: {_mode},
                      onSelectionChanged: _saving
                          ? null
                          : (selection) => setState(() {
                                _mode = selection.first;
                                _formKey.currentState?.reset();
                              }),
                      style: SegmentedButton.styleFrom(
                        selectedBackgroundColor: AppTheme.violet,
                        selectedForegroundColor: Colors.white,
                        foregroundColor: AppTheme.textDark,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Username field
                    TextFormField(
                      controller: _controller,
                      autofocus: true,
                      textInputAction: TextInputAction.done,
                      enabled: !_saving,
                      decoration: InputDecoration(
                        labelText:
                            _isCreate ? 'Choose a username' : 'Your username',
                        hintText: 'e.g. harish01',
                        helperText: _isCreate
                            ? 'At least 6 characters, must be unique'
                            : 'The name you used when you first set up',
                      ),
                      validator: (value) {
                        final text = (value ?? '').trim();
                        if (text.isEmpty) return 'Please enter a username';
                        // Only creation has to satisfy the backend's rule.
                        if (_isCreate && text.length < 6) {
                          return 'Username must be at least 6 characters';
                        }
                        return null;
                      },
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 20),

                    // Continue button
                    ElevatedButton(
                      onPressed: _saving ? null : _submit,
                      child: _saving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(_isCreate ? 'GET STARTED' : 'CONTINUE'),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'No password needed — this prototype has no login.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
