import 'dart:convert';
import 'dart:developer';

import 'package:chucker_flutter/src/helpers/shared_preferences_manager.dart';
import 'package:chucker_flutter/src/models/api_response.dart';
import 'package:chucker_flutter/src/view/helper/chucker_ui_helper.dart';
import 'package:get/get.dart';
import 'package:get/get_connect/http/src/interceptors/get_modifiers.dart';
import 'package:get/get_connect/http/src/request/request.dart';

/// [ChuckerGetConnectInterceptor] adds support for `chucker_flutter` in [GetConnect] library.
class ChuckerGetConnectInterceptor {
  late DateTime _requestTime;

  /// Intercept a request before it's sent
  RequestModifier<dynamic> onRequest() {
    return (request) {
      _requestTime = DateTime.now();
      return request;
    };
  }

  /// Intercept a response after it's received
  ResponseModifier<dynamic> onResponse() {
    return (request, response) async {
      try {
        await SharedPreferencesManager.getInstance().getSettings();

        if (!ChuckerFlutter.isDebugMode && !ChuckerFlutter.showOnRelease) {
          return response;
        }

        final method = request.method;
        final statusCode = response.statusCode ?? -1;
        final path = request.url.path;

        ChuckerUiHelper.showNotification(
          method: method,
          statusCode: statusCode,
          path: path,
          requestTime: _requestTime,
        );

        await _saveResponse(request, response);

        log('ChuckerFlutter: $method:$path - $statusCode saved.');
      } catch (e) {
        log('ChuckerFlutter: Error saving response: $e');
      }
      return response;
    };
  }

  /// Register this interceptor with a GetConnect httpClient
  void register(GetHttpClient httpClient) {
    httpClient
      ..addRequestModifier(onRequest())
      ..addResponseModifier(onResponse());
  }

  /// Register this interceptor with an ApiProvider that extends GetConnect
  void registerWith(GetConnect connect) {
    connect.httpClient.addRequestModifier(onRequest());
    connect.httpClient.addResponseModifier(onResponse());
  }

  /// Handle HTTP errors
  void onHttpError<T>(
    Response<T> response, {
    Request<T>? request,
    bool isDioRequest = false,
  }) async {
    await SharedPreferencesManager.getInstance().getSettings();

    if (!ChuckerFlutter.isDebugMode && !ChuckerFlutter.showOnRelease) {
      return;
    }

    final method = request?.method ?? 'UNKNOWN';
    final statusCode = response.statusCode ?? -1;
    final path = request?.url.path ?? 'UNKNOWN';

    ChuckerUiHelper.showNotification(
      method: method,
      statusCode: statusCode,
      path: path,
      requestTime: _requestTime,
    );

    await _saveError(request, response);

    log('ChuckerFlutter: $method:$path - $statusCode saved.');
  }

  Future<void> _saveResponse<T>(
      Request<T> request, Response<T> response) async {
    await SharedPreferencesManager.getInstance().addApiResponse(
      ApiResponse(
        body: response.body,
        path: request.url.path,
        baseUrl: request.url.origin,
        method: request.method,
        statusCode: response.statusCode ?? -1,
        connectionTimeout: 0, // GetConnect doesn't expose this
        contentType: request.headers['content-type'],
        headers: request.headers.cast<String, dynamic>(),
        queryParameters: request.url.queryParameters.cast<String, dynamic>(),
        receiveTimeout: 0, // GetConnect doesn't expose this
        request: _processRequestBody(request),
        requestSize: _calculateRequestSize(request) ?? 0,
        requestTime: _requestTime,
        responseSize: await _calculateResponseSize(response) ?? 0,
        responseTime: DateTime.now(),
        responseType: 'json', // Default for GetConnect
        sendTimeout: 0, // GetConnect doesn't expose this
        checked: false,
        clientLibrary: 'GetConnect',
      ),
    );
  }

  Future<void> _saveError<T>(Request<T>? request, Response<T> response) async {
    if (request == null) {
      return;
    }

    await SharedPreferencesManager.getInstance().addApiResponse(
      ApiResponse(
        body: _getJson(response.bodyString ?? ''),
        path: request.url.path,
        baseUrl: request.url.origin,
        method: request.method,
        statusCode: response.statusCode ?? -1,
        connectionTimeout: 0, // GetConnect doesn't expose this
        contentType: request.headers['content-type'],
        headers: request.headers.cast<String, dynamic>(),
        queryParameters: request.url.queryParameters.cast<String, dynamic>(),
        receiveTimeout: 0, // GetConnect doesn't expose this
        request: await _processRequestBody(request),
        requestSize: _calculateRequestSize(request) ?? 0,
        requestTime: _requestTime,
        responseSize: await _calculateResponseSize(response) ?? 0,
        responseTime: DateTime.now(),
        responseType: 'json', // Default for GetConnect
        sendTimeout: 0, // GetConnect doesn't expose this
        checked: false,
        clientLibrary: 'GetConnect',
      ),
    );
  }

  Future<dynamic> _processRequestBody<T>(Request<T> request) async {
    try {
      // Ensure we listen only once by collecting the stream immediately
      final allBytes =
          await request.bodyBytes.expand((chunk) => chunk).toList();

      // Decode bytes to a UTF-8 string
      final bodyString = utf8.decode(allBytes);

      // Try decoding as JSON, fallback to returning the raw string
      try {
        return jsonDecode(bodyString);
      } catch (_) {
        return bodyString; // If not JSON, return the plain string
      }
    } catch (e) {
      return 'Error processing request body: $e';
    }
  }

  double? _calculateRequestSize<T>(Request<T> request) {
    return request.contentLength?.toDouble();
  }

  Future<double>? _calculateResponseSize<T>(Response<T> response) async {
    if (response.bodyBytes != null) {
      return (await response.bodyBytes?.length ?? 0).toDouble();
    }
    return 0;
  }

  Map<String, dynamic> _getJson(String data) {
    try {
      return jsonDecode(data) as Map<String, dynamic>;
    } catch (e) {
      return {};
    }
  }
}

/// Extension to ChuckerFlutter to support GetConnect
extension ChuckerGetConnectExtension on ChuckerFlutter {
  /// Handle HTTP response from GetConnect
  static void onHttpResponse<T>(
    Response<T> response, {
    Request<T>? request,
    bool isDioRequest = false,
  }) {
    ChuckerGetConnectInterceptor()
      .._requestTime =
          DateTime.now().subtract(const Duration(milliseconds: 100))
      ..onHttpError(response, request: request, isDioRequest: isDioRequest);
  }
}
