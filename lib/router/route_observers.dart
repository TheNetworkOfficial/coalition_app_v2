import 'package:flutter/widgets.dart';

/// Global route observer so individual pages can subscribe to navigation events.
final RouteObserver<PageRoute<dynamic>> appRouteObserver =
    RouteObserver<PageRoute<dynamic>>();
