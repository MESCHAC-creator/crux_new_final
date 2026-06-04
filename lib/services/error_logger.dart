import 'package:logger/logger.dart';

class ErrorLogger {
  static final ErrorLogger _instance = ErrorLogger._();
  final _logger = Logger();

  ErrorLogger._();
  factory ErrorLogger() => _instance;

  /// Log and optionally rethrow errors
  void logError(String context, dynamic error, {StackTrace? stackTrace, bool shouldRethrow = false}) {
    final msg = '❌ [$context] ${error.toString()}';
    _logger.e(msg, stackTrace: stackTrace ?? StackTrace.current);
    if (shouldRethrow) throw error;
  }

  /// Wrap async operations with automatic error logging
  Future<T?> wrapAsync<T>(String context, Future<T> Function() fn) async {
    try {
      return await fn();
    } catch (e, st) {
      logError(context, e, stackTrace: st);
      return null;
    }
  }

  /// Log Firestore operation failure
  void logFirestoreError(String operation, String docPath, dynamic error) {
    logError('Firestore.$operation($docPath)', error);
  }

  /// Log and queue failed operation for retry
  void logFailedOperation(String operationId, String operation, dynamic error) {
    _logger.w('⚠️ [Retry Queue] Failed operation: $operationId - $operation - $error');
  }
}
