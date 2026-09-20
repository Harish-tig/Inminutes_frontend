import 'package:flutter/material.dart';

import '../models/participant.dart';
import '../utils/app_theme.dart';
import 'state_views.dart';

/// One row of the participants list. The host is shown as a separate tile with
/// [isHost] set, because the backend gives the host no ready flag at all.
class ParticipantTile extends StatelessWidget {
  final String name;
  final bool isHost;
  final bool isYou;
  final Participant? participant;

  /// Set only when the viewer is the host and the session is still open.
  final VoidCallback? onRemove;

  const ParticipantTile({
    super.key,
    required this.name,
    required this.isHost,
    required this.isYou,
    this.participant,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final ready = participant?.ready ?? false;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: isHost ? AppTheme.violetSoft : AppTheme.background,
            child: Text(
              name.isEmpty ? '?' : name.characters.first.toUpperCase(),
              style: TextStyle(
                color: isHost ? AppTheme.violet : AppTheme.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              isYou ? '$name (you)' : name,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.itemName,
            ),
          ),

          // Host badge, or the participant's ready status
          if (isHost)
            const StatusChip(
              label: 'HOST',
              color: AppTheme.violet,
              background: AppTheme.violetSoft,
              icon: Icons.star_rounded,
            )
          else if (ready)
            const StatusChip(
              label: 'READY',
              color: AppTheme.success,
              background: AppTheme.successSoft,
              icon: Icons.check_circle,
            )
          else
            const StatusChip(
              label: 'STILL BROWSING',
              color: AppTheme.textMuted,
              background: AppTheme.neutralSoft,
              icon: Icons.schedule,
            ),

          // Host-only: remove this participant from the session
          if (onRemove != null)
            IconButton(
              tooltip: 'Remove from group',
              onPressed: onRemove,
              visualDensity: VisualDensity.compact,
              constraints:
                  const BoxConstraints.tightFor(width: 34, height: 34),
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.person_remove_outlined,
                  size: 18, color: AppTheme.textMuted),
            ),
        ],
      ),
    );
  }
}
