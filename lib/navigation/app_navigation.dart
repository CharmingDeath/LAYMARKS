import 'package:flutter/material.dart';

class AppRoutes {
  static const String splash = '/';
  static const String dashboard = '/dashboard';
  static const String news = '/news';
  static const String companies = '/companies';
  static const String saved = '/saved';
}

class AppNavigation {
  static void go(BuildContext context, int index) {
    String route;
    switch (index) {
      case 0:
        route = AppRoutes.dashboard;
        break;
      case 1:
        route = AppRoutes.news;
        break;
      case 2:
        route = AppRoutes.companies;
        break;
      case 3:
        route = AppRoutes.saved;
        break;
      default:
        route = AppRoutes.dashboard;
    }
    Navigator.of(context).pushReplacementNamed(route);
  }
}
