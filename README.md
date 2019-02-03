# ntlm_dio

Dart/Flutter NTLM Authentication as an interceptor for 
[dio](https://github.com/flutterchina/dio).

## Getting Started

Based on (and depends on) https://github.com/mrbbot/ntlm

## Example

```dart
fetch() async {
  final baseOptions = BaseOptions();
  final credentials = Credentials(
    domain: 'testdomain',
    username: 'testuser',
    password: 'password'
  );
  Dio dio = Dio(baseOptions);
  final cookieJar = CookieJar();
  dio.interceptors.add(CookieManager(cookieJar));
  dio.interceptors.add(NtlmInterceptor(credentials, () =>
    Dio(baseOptions)..interceptors.add(CookieManager(cookieJar))
  ));

  final response = await dio.get(config.url);
}
```

