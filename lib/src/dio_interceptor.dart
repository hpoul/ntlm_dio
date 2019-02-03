part of ntlm_dio;

final log = new Logger("ntlm.dio_interceptor");

/// Tried to authenticate, but (probably) got invalid credentials (username or password).
class InvalidCredentialsException extends DioError {
  final String message;
  final DioError source;

  InvalidCredentialsException(this.message, this.source)
      : super(
          response: source.response,
          message: source.message,
          type: source.type,
          stackTrace: source.stackTrace,
        );

  @override
  String toString() {
    return 'InvalidCredentialsException{message=${message},source=${source}}';
  }
}

class Credentials {
  String domain;
  String workstation;
  String username;
  String password;

  Credentials({this.domain = '', this.workstation = '', @required this.username, @required this.password});
}

typedef Dio AuthDioCreator();

class NtlmInterceptor extends Interceptor {
  final Credentials credentials;
  final AuthDioCreator authDioCreator;
//  final CookieJar cookieJar;

  NtlmInterceptor(this.credentials, [this.authDioCreator]);

  onRequest(Options options) {
    log.finer("We are sending request. ${options.headers}");
    return options;
  }

  onResponse(Response response) {
    log.fine('Intercepted onSuccess. ${response.statusCode}}');
    return response;
  }

  onError(DioError e) async {
    try {
      log.finer('Intercepted onError. ${e.response?.statusCode} for request ${e.response?.request?.path}');
      if (e.response?.statusCode != HttpStatus.unauthorized) {
        return e;
      }
      log.finer('headers: ${_debugHttpHeaders(e.response.headers)}');
      final authHeader = e.response.headers[HttpHeaders.wwwAuthenticateHeader];
      if (authHeader == null || authHeader.first != 'NTLM') {
        log.warning('Got a HTTP unauthorized response code, but no NTLM authentication header was set.');
        return e;
      }

      // FIXME: remove username from log.
      log.fine('Trying to authenticate request (${credentials.domain}/${credentials.username}).');

      Dio authDio = authDioCreator == null ? Dio() : authDioCreator();
//      authDio.interceptors.add(CookieManager(cookieJar));
//        authDio.cookieJar = dio.cookieJar;

      String msg1 = createType1Message(
        domain: credentials.domain,
        workstation: credentials.workstation,
      );
      final res1 = await (authDio
          .get(e.response.request.path,
              options: e.response.request.merge(
                  validateStatus: (status) => status == HttpStatus.unauthorized || status == HttpStatus.ok,
                  headers: {HttpHeaders.authorizationHeader: msg1}..addAll(e.response.request.headers)))
          .catchError((error, stackTrace) {
        log.fine('Error during type1 message.', error, stackTrace);
        return Future.error(error, stackTrace);
      }));
      String res2Authenticate = res1.headers[HttpHeaders.wwwAuthenticateHeader]?.first;
      log.finer('Received type1 message response ${res2Authenticate}');
      if (res2Authenticate == null) {
        log.warning('No Authenticate header found for response from ${e.response.request.path}.', e, e.stackTrace);
        return e;
      }
      if (!res2Authenticate.startsWith("NTLM ")) {
        log.warning(
            'Type1 message response does not return NTLM auth header. ${res1.headers[HttpHeaders.wwwAuthenticateHeader].toList()}');
        return e;
      }
      Type2Message msg2 = parseType2Message(res2Authenticate);

      String msg3 = createType3Message(msg2,
          domain: credentials.domain,
          workstation: credentials.workstation,
          username: credentials.username,
          password: credentials.password);

      final res2 = await (authDio
          .get(e.response.request.path,
              options: e.response.request
                  .merge(headers: {HttpHeaders.authorizationHeader: msg3}..addAll(e.response.request.headers)))
          .catchError((error, stackTrace) {
        if (error is DioError) {
          log.fine('Error during authentication request. ${error?.response?.headers}', error, stackTrace);
          if (error.type == DioErrorType.RESPONSE && error.response?.statusCode == HttpStatus.unauthorized) {
            return Future<Response<dynamic>>.error(InvalidCredentialsException('invalid authentication.', error));
          }
        }
        return Future<Response<dynamic>>.error(error, stackTrace);
      }));
      log.finer('Received type3 message response. ${res2?.statusCode}.');

      return res2 as Response<dynamic>;
    } catch (e, stackTrace) {
      String msg = 'error:${e?.runtimeType}';
      if (e is DioError) {
        msg = 'code: ${e.response?.statusCode} / ${_debugHttpHeaders(e.response?.headers)}';
      }
      log.warning('Error while trying to authenticate. ${msg}', e, stackTrace);
      rethrow;
    } finally {
      log.finer('Finished onError handler.');
    }
  }
}

void addNtlmInterceptor(Dio dio, Credentials credentials, CookieJar cookieJar) {
  dio.interceptors.add(InterceptorsWrapper());
}

String _debugHttpHeaders(HttpHeaders headers) {
  final ret = Map<String, List<String>>();
  headers.forEach((key, values) {
    ret[key] = values;
  });
  return ret.toString();
}
