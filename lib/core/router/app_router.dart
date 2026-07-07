import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/login_screen.dart';
import '../../features/billing/billing_screen.dart';
import '../../features/products/products_screen.dart';
import '../../features/reports/daily_sales_screen.dart';
import '../../features/reports/inventory_report_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/bills/past_bills_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/login',
    routes: [
      GoRoute(
        path: '/',
        redirect: (_, __) => '/billing',
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/billing',
        builder: (context, state) => const BillingScreen(),
      ),
      GoRoute(
        path: '/past-bills',
        builder: (context, state) => const PastBillsScreen(),
      ),
      GoRoute(
        path: '/products',
        builder: (context, state) => const ProductsScreen(),
      ),
      GoRoute(
        path: '/reports',
        builder: (context, state) => const DailySalesScreen(),
      ),
      GoRoute(
        path: '/inventory-report',
        builder: (context, state) => const InventoryReportScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
  );
});
