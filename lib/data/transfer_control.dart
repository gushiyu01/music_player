import 'dart:async';

import 'baidu_client.dart';

class TransferControl {
  final _abort = Completer<void>();
  bool get cancelled => _abort.isCompleted;
  Future<void> get aborted => _abort.future;
  void cancel() {
    if (!cancelled) _abort.complete();
  }

  void check() {
    if (cancelled) {
      throw const DriveException('传输已取消', code: 'cancelled');
    }
  }
}
