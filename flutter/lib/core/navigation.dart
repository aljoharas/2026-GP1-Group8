import 'package:flutter/material.dart';

/// Lets code outside the widget tree (push notification taps) push a route
/// without needing a BuildContext.
final navigatorKey = GlobalKey<NavigatorState>();
