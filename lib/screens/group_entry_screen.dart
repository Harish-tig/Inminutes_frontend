import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_service.dart';
import '../state/user_state.dart';
import '../utils/app_theme.dart';
import '../utils/ui.dart';
import 'group_screen.dart';

/// Start of the group flow: host a new group, or open one with a code.
///
/// The same form handles joining and **re-entering**. The host is never a
/// participant and a returning participant has already joined, so both would be
/// rejected by `POST .../join` — the code checks membership first and only
/// joins when the caller really is new to the session.
class GroupEntryScreen extends StatefulWidget {
  /// Pre-fills the code, used by the home screen's "rejoin" action.
  final String? initialCode;

  const GroupEntryScreen({super.key, this.initialCode});

  @override
  State<GroupEntryScreen> createState() => _GroupEntryScreenState();
}

class _GroupEntryScreenState extends State<GroupEntryScreen> {
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  final _hostNameController = TextEditingController();

  bool _creating = false;
  bool _joining = false;

  @override
  void initState() {
    super.initState();
    _codeController.text = widget.initialCode ?? '';
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _hostNameController.dispose();
    super.dispose();
  }

  /// Host path — `POST /api/group-sessions` returns just the join code.
  Future<void> _createGroup() async {
    final userState = context.read<UserState>();
    setState(() => _creating = true);
    try {
      final joinCode = await ApiService.createGroupSession(
        userState.userId,
        displayName: _hostNameController.text.trim(),
      );
      await userState.rememberGroup(joinCode);
      if (!mounted) return;
      Navigator.pushReplacement(context, GroupScreen.route(context, joinCode));
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  /// Opens the session: joins first if the caller is not already a member.
  Future<void> _openGroup() async {
    final userState = context.read<UserState>();
    final joinCode = _codeController.text.trim().toUpperCase();

    if (joinCode.isEmpty) {
      showSnack(context, 'Enter the code the host shared');
      return;
    }

    setState(() => _joining = true);
    try {
      // Membership decides whether this is a join or a re-entry. The host and
      // anyone who already joined go straight back in.
      final session = await ApiService.getGroupSession(joinCode);

      if (!session.isMember(userState.userId)) {
        final displayName = _nameController.text.trim();
        if (displayName.isEmpty) {
          if (mounted) {
            showSnack(context, 'Enter a display name to join this group');
          }
          return;
        }
        await ApiService.joinGroupSession(
            joinCode, userState.userId, displayName);
      }

      await userState.rememberGroup(joinCode);
      if (!mounted) return;
      Navigator.pushReplacement(context, GroupScreen.route(context, joinCode));
    } catch (e) {
      // Backend wording reaches the user unchanged: "Display name already
      // exists in this group", "Group session not found", etc.
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _creating || _joining;

    return Scaffold(
      appBar: AppBar(title: const Text('GROUP ORDER')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: AppTheme.pagePadding,
          children: [
            // Host a new group
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.add_circle_outline,
                            color: AppTheme.violet),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text('START A NEW GROUP',
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.sectionHeading),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'You become the host. Share the join code, and place the '
                      'order once everyone is ready.',
                      style: TextStyle(color: AppTheme.textMuted, height: 1.4),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _hostNameController,
                      enabled: !busy,
                      maxLength: 30,
                      decoration: const InputDecoration(
                        labelText: 'Your display name',
                        hintText: 'Harish',
                        helperText: 'Optional — your username is used instead',
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: busy ? null : _createGroup,
                      child: _creating
                          ? const _ButtonSpinner()
                          : const Text('CREATE GROUP'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Join, or go back into a group already joined
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.login, color: AppTheme.violet),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text('OPEN A GROUP',
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.sectionHeading),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Enter a code to join a new group, or to go back into one '
                      'you are already in.',
                      style: TextStyle(color: AppTheme.textMuted, height: 1.4),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _codeController,
                      enabled: !busy,
                      textCapitalization: TextCapitalization.characters,
                      maxLength: 8,
                      decoration: const InputDecoration(
                        labelText: 'Join code',
                        hintText: 'IB3F4F8J',
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _nameController,
                      enabled: !busy,
                      maxLength: 30,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: 'Your display name',
                        hintText: 'Bob',
                        helperText:
                            'Only needed the first time you join a group',
                        counterText: '',
                      ),
                      onSubmitted: (_) => _openGroup(),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: busy ? null : _openGroup,
                      child: _joining
                          ? const _ButtonSpinner()
                          : const Text('OPEN GROUP'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ButtonSpinner extends StatelessWidget {
  const _ButtonSpinner();

  @override
  Widget build(BuildContext context) => const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
      );
}
