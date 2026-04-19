import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Global provider to share the last completed session ID across screens.
/// Agent 1 sets this when a session completes, Agent 3 reads it automatically.

class SessionState {
  final String? lastSessionId;
  final bool isCompleted;

  SessionState({this.lastSessionId, this.isCompleted = false});

  SessionState copyWith({String? lastSessionId, bool? isCompleted}) {
    return SessionState(
      lastSessionId: lastSessionId ?? this.lastSessionId,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }
}

class SessionNotifier extends Notifier<SessionState> {
  @override
  SessionState build() => SessionState();

  void setActiveSession(String sessionId) {
    state = state.copyWith(lastSessionId: sessionId, isCompleted: false);
  }

  void markCompleted(String sessionId) {
    state = state.copyWith(lastSessionId: sessionId, isCompleted: true);
  }

  void clear() {
    state = SessionState();
  }
}

final sessionProvider = NotifierProvider<SessionNotifier, SessionState>(SessionNotifier.new);
