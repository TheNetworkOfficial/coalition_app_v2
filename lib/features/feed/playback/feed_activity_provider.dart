import 'package:flutter_riverpod/legacy.dart';

/// Keep this index in sync with the router's branch order:
/// Per analysis, the Feed is the FIRST branch (index 0).
const int kFeedBranchIndex = 0;

/// True when the Feed branch is currently the visible tab.
final feedActiveProvider = StateProvider<bool>((ref) => false);
