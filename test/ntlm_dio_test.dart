import 'dart:convert';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:io' show File, HttpHeaders, HttpStatus, Platform;
import 'package:path/path.dart' as p;
import "package:system_info/system_info.dart";

import 'package:ntlm_dio/ntlm_dio.dart';
import './_test_utils.dart';

class NtlmTestConfig {
  String url;
  String domain;
  String username;
  String password;
  Map<String, String> headers;

  static const ENV_NAME = 'NTLM_TEST_CONFIG';
  static const EXAMPLE_JSON = '{"url": "", "domain": "", "username": "", "password": ""}';

  Credentials get credentials => Credentials(username: username, password: password, domain: domain);

  factory NtlmTestConfig.fromEnvironment() {
    final jsonConfig = Platform.environment[ENV_NAME];
    if (jsonConfig == null) {
      throw StateError('Expected environment variable ${ENV_NAME} - for example: ${EXAMPLE_JSON}');
    }
    return NtlmTestConfig.fromJsonString(jsonConfig);
  }

  factory NtlmTestConfig.fromFile() {
    final name = '.ntlm_dio.test.config.json';
    final paths = [name, p.join(SysInfo.userDirectory, name)];
    for(final path in paths) {
      final f = File(path);
      if (f.existsSync()) {
        return NtlmTestConfig.fromJsonString(f.readAsStringSync());
      }
    }
    throw StateError('Expected to find config in one of the following paths: ${paths}');
  }

  factory NtlmTestConfig.fromJsonString(String jsonString) {
    final jsonValue = json.decode(jsonString) as Map;
    return NtlmTestConfig.fromJson(jsonValue.cast<String, dynamic>());
  }

  factory NtlmTestConfig.fromJson(Map<String, dynamic> json) {
    Map<String, String> headers;
    final headersMap = json['headers'];
    if (headersMap is Map) {
      headers = headersMap.cast<String, String>();
    }
    return NtlmTestConfig(
        url: json['url'],
        domain: json['domain'] ?? '',
        username: json['username'],
        password: json['password'],
        headers: headers);
  }

  NtlmTestConfig({this.url, this.domain, this.username, this.password, this.headers});
}

void main() {
  final config = NtlmTestConfig.fromFile();
  initTestLogging();
  test('test ntlm auth', () async {
    final baseOptions = BaseOptions(headers: config.headers);
    Dio dio = Dio(baseOptions);
    final cookieJar = CookieJar();
    dio.interceptors.add(CookieManager(cookieJar));
    dio.interceptors.add(NtlmInterceptor(config.credentials, () =>
      Dio(baseOptions)..interceptors.add(CookieManager(cookieJar))
    ));

    final response = await dio.get(config.url);
    expect(response.statusCode, HttpStatus.ok);
  });
}
