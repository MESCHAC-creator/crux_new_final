import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import '../utils/constants.dart';

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  late Dio _dio;
  final _logger = Logger();

  factory ApiClient() => _instance;

  ApiClient._internal() {
    _dio = Dio(
      BaseOptions(
        connectTimeout: AppConstants.requestTimeout,
        receiveTimeout: AppConstants.requestTimeout,
        contentType: 'application/json',
      ),
    );

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        _logger.i('📤 ${options.method} ${options.path}');
        return handler.next(options);
      },
      onResponse: (response, handler) {
        _logger.i('📥 ${response.statusCode}');
        return handler.next(response);
      },
      onError: (error, handler) {
        _logger.e('❌ API: ${error.message}');
        return handler.next(error);
      },
    ));
  }

  Future<dynamic> get(String url) async {
    try {
      final response = await _dio.get(url);
      return response.data;
    } catch (e) {
      _logger.e('❌ GET: $e');
      rethrow;
    }
  }

  Future<dynamic> post(String url, {dynamic data}) async {
    try {
      final response = await _dio.post(url, data: data);
      return response.data;
    } catch (e) {
      _logger.e('❌ POST: $e');
      rethrow;
    }
  }
}
