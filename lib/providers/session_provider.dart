import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Global provider to share the last completed session ID across screens.
/// Agent 1 sets this when a session completes, Agent 3 reads it automatically.

class SessionState {
  final String? lastSessionId;
  final bool isCompleted;
  final int refreshToken; // Incremented to signal that advice should be re-fetched
  /// 'home' = chăm sóc tại nhà (advice from symptoms)
  /// 'hospital' = đi khám (advice from doctor's conclusion)
  final String? careMode;

  SessionState({
    this.lastSessionId,
    this.isCompleted = false,
    this.refreshToken = 0,
    this.careMode,
  });

  SessionState copyWith({
    String? lastSessionId,
    bool? isCompleted,
    int? refreshToken,
    String? careMode,
  }) {
    return SessionState(
      lastSessionId: lastSessionId ?? this.lastSessionId,
      isCompleted: isCompleted ?? this.isCompleted,
      refreshToken: refreshToken ?? this.refreshToken,
      careMode: careMode ?? this.careMode,
    );
  }
}

class SessionNotifier extends Notifier<SessionState> {
  @override
  SessionState build() => SessionState();

  void setActiveSession(String sessionId) {
    state = state.copyWith(lastSessionId: sessionId, isCompleted: false);
  }

  /// Mark session completed with the care mode from Agent 1's decision.
  /// [careMode] should be 'home' or 'hospital'.
  void markCompleted(String sessionId, {String? careMode}) {
    state = SessionState(
      lastSessionId: sessionId,
      isCompleted: true,
      refreshToken: state.refreshToken,
      careMode: careMode ?? state.careMode,
    );
  }

  /// Signal that health advice has been updated and needs re-fetching.
  void invalidateAdvice() {
    state = state.copyWith(refreshToken: state.refreshToken + 1);
  }

  void clear() {
    state = SessionState();
  }
}

final sessionProvider = NotifierProvider<SessionNotifier, SessionState>(SessionNotifier.new);
