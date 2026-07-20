import 'package:logger/logger.dart' as logger_pkg;

final logger = logger_pkg.Logger(
  printer: logger_pkg.PrettyPrinter(
    methodCount: 2,
    errorMethodCount: 8,
    lineLength: 120,
    colors: true,
    printEmojis: true,
    printTime: false,
  ),
);
