import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/order.dart';
import '../services/api_service.dart';
import '../state/user_state.dart';
import '../utils/app_theme.dart';
import '../utils/ui.dart';
import '../widgets/state_views.dart';
import 'group_orders_screen.dart';

/// Order history — normal orders the user placed plus group orders they were
/// part of, newest first.
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  List<Order> _orders = [];
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
      final orders =
          await ApiService.getOrders(context.read<UserState>().userId);
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
      appBar: AppBar(
        title: const Text('MY ORDERS'),
        actions: [
          IconButton(
            tooltip: 'Groups I hosted',
            icon: const Icon(Icons.groups_rounded),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const GroupOrdersScreen()),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Builder(
          builder: (context) {
            if (_loading) {
              return const LoadingView(message: 'Loading orders...');
            }
            if (_error != null) {
              return ErrorView(message: _error!, onRetry: _load);
            }
            if (_orders.isEmpty) {
              return const EmptyView(
                icon: Icons.receipt_long_outlined,
                message: 'You have not placed any orders yet.',
              );
            }

            // Order list
            return RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                padding: AppTheme.pagePadding,
                itemCount: _orders.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) =>
                    _OrderCard(order: _orders[index]),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final Order order;
  const _OrderCard({required this.order});

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
            Row(
              children: [
                StatusChip(
                  label: order.isGroup ? 'GROUP ORDER' : 'INDIVIDUAL',
                  color: order.isGroup ? AppTheme.violet : AppTheme.textMuted,
                  background: order.isGroup
                      ? AppTheme.violetSoft
                      : AppTheme.neutralSoft,
                  icon: order.isGroup
                      ? Icons.groups_rounded
                      : Icons.person_outline,
                ),
                const Spacer(),
                Text(dateText, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 12),

            // Item snapshot lines
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
                    // Group orders record who added each line
                    if (line.addedByName != null) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          line.addedByName!,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                    const SizedBox(width: 10),
                    Text(
                      formatPrice(line.lineTotal),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(order.orderStatus.toUpperCase(),
                    style: const TextStyle(
                      color: AppTheme.success,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    )),
                Text(
                  formatPrice(order.orderAmt),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    fontStyle: FontStyle.italic,
                    color: AppTheme.violet,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
