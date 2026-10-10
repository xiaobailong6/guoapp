import 'package:flutter/material.dart';

Route<void> playerRoute(Widget child) => PageRouteBuilder<void>(
  opaque: true,
  transitionDuration: Duration.zero,
  reverseTransitionDuration: Duration.zero,
  pageBuilder: (context, animation, secondaryAnimation) => child,
  transitionsBuilder: (context, animation, secondaryAnimation, child) => child,
);
