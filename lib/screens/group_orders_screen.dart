import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/hosted_group_order.dart';
import '../services/api_service.dart';
import '../state/user_state.dart';
import '../utils/app_theme.dart';
import '../utils/ui.dart';
import '../widgets/state_views.dart';

/// Group orders this user hosted, each with the split of who owes what.
///
/// Sessions they merely joined are not here — those stay in the ordinary order
/// history. That is the backend's rule, not a filter applied locally.
class GroupOrdersScreen extends StatefulWidget {
  const GroupOrdersScreen({super.key});

  @override
  State<GroupOrdersScreen> createState() => _GroupOrdersScreenState();
}

class _GroupOrdersScreenState extends State<GroupOrdersScreen> {
  List<HostedGroupOrder> _orders = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final orders = await ApiService.getHostedGroupOrders(
        context.read<UserState>().userId,
      );
      if (mounted) setState(() => _orders = orders);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('GROUPS I HOSTED')),
      body: SafeArea(
        top: false,
        child: Builder(
          builder: (context) {
            if (_loading) {
              return const LoadingView(message: 'Loading group orders...');
            }
            if (_error != null) {
              return ErrorView(message: _error!, onRetry: _load);
            }
            if (_orders.isEmpty) {
              return const EmptyView(
                icon: Icons.groups_outlined,
                message: 'You have not hosted a group order yet.\n'
                    'Group orders you joined are in My orders.',
              );
            }

            // Hosted group orders, newest first
            return RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                padding: AppTheme.pagePadding,
                itemCount: _orders.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) =>
                    _HostedOrderCard(order: _orders[index]),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _HostedOrderCard extends StatelessWidget {
  final HostedGroupOrder order;
  const _HostedOrderCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final date = order.orderDate;
    final dateText = date == null
        ? ''
        : '${date.day.toString().padLeft(2, '0')}/'
            '${date.month.toString().padLeft(2, '0')}/${date.year}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Session and total
            Row(
              children: [
                if (order.joinCode.isNotEmpty)
                  StatusChip(
                    label: order.joinCode,
                    color: AppTheme.violet,
                    background: AppTheme.violetSoft,
                    icon: Icons.groups_rounded,
                  ),
                const Spacer(),
                Text(dateText, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    '${order.itemCount} item(s) · ${order.peopleCount} people',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                Text(
                  formatPrice(order.orderAmt),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    fontStyle: FontStyle.italic,
                    color: AppTheme.violet,
                  ),
                ),
              ],
            ),
            const Divider(height: 22),

            // Who owes what
            const Text('WHO OWES WHAT', style: AppTheme.kicker),
            const SizedBox(height: 8),
            ...order.breakdown.map((row) => _BreakdownRowTile(row: row)),
            const Divider(height: 22),

            // The ordered lines, attributed
            const Text('ITEMS', style: AppTheme.kicker),
            const SizedBox(height: 8),
            ...order.products.map(
              (line) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${line.qty} × ${line.name}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      line.addedByName,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      formatPrice(line.lineAmt),
                      style: const TextStyle(fontWeight: FontWeight.w700),
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

/// One person's share. People who ordered nothing are shown too, greyed out,
/// so nobody silently disappears from the split.
class _BreakdownRowTile extends StatelessWidget {
  final BreakdownRow row;
  const _BreakdownRowTile({required this.row});

  @override
  Widget build(BuildContext context) {
    final muted = row.orderedNothing;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              row.displayName,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.itemName.copyWith(
                fontSize: 14,
                color: muted ? AppTheme.textMuted : AppTheme.textDark,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            muted ? 'nothing ordered' : '${row.qty} item(s)',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(width: 10),
          Text(
            formatPrice(row.amount),
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: muted ? AppTheme.textMuted : AppTheme.violet,
            ),
          ),
        ],
      ),
    );
  }
}
