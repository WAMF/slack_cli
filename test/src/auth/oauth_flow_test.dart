import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_slack/src/auth/oauth_flow.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockHttpClient extends Mock implements http.Client {}

class _MockLogger extends Mock implements Logger {}

class _MockProcess extends Mock implements Process {}

void main() {
  group('OAuthFlow', () {
    late _MockHttpClient httpClient;
    late _MockLogger logger;
    late _MockProcess process;
    late Directory tempDir;

    const tokenResponse = {
      'ok': true,
      'team': {'id': 'T123', 'name': 'Test Team'},
      'authed_user': {'id': 'U123', 'access_token': 'xoxp-test'},
    };

    setUpAll(() {
      registerFallbackValue(Uri.parse('https://example.com'));
    });

    setUp(() {
      httpClient = _MockHttpClient();
      logger = _MockLogger();
      process = _MockProcess();

      when(() => process.exitCode).thenAnswer((_) async => 0);

      when(() => logger.info(any())).thenReturn(null);
      when(() => logger.err(any())).thenReturn(null);

      tempDir = Directory.systemTemp.createTempSync('oauth_flow_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    /// Extracts the callback port from the authorize URL's redirect_uri.
    int callbackPortFrom(Uri authorizeUrl) {
      final redirectUri = Uri.parse(
        authorizeUrl.queryParameters['redirect_uri']!,
      );
      return redirectUri.port;
    }

    /// Sends a GET to the local HTTPS callback server, accepting
    /// self-signed certificates. Returns the response body.
    Future<String> sendCallback(
      String queryString, {
      required int callbackPort,
    }) async {
      final client = HttpClient()..badCertificateCallback = (_, _, _) => true;
      final request = await client.getUrl(
        Uri.parse('https://localhost:$callbackPort/callback?$queryString'),
      );
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      client.close();
      return body;
    }

    OAuthFlow createFlow({
      required Future<Process> Function(String, List<String>) processStarter,
      Future<HttpServer> Function(
        Object address,
        int port,
        SecurityContext context, {
        int backlog,
        bool shared,
        bool v6Only,
      })?
      bindServer,
    }) {
      return OAuthFlow(
        clientId: 'test-id',
        clientSecret: 'test-secret',
        logger: logger,
        httpClient: httpClient,
        processStarter: processStarter,
        bindServer: bindServer,
        configDirectory: tempDir,
        port: 0,
      );
    }

    /// Fires a callback request without awaiting. Errors are expected
    /// when the server closes before the response is fully read.
    void fireCallback(String queryString, {required int callbackPort}) {
      unawaited(
        sendCallback(
          queryString,
          callbackPort: callbackPort,
        ).onError((_, _) => ''),
      );
    }

    /// Helper: extracts the state param from a Slack authorize URL.
    String stateFrom(Uri url) => url.queryParameters['state']!;

    test('includes state parameter in authorize URL', () async {
      late Uri capturedUrl;

      when(
        () => httpClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(jsonEncode(tokenResponse), 200),
      );

      final flow = createFlow(
        processStarter: (command, args) async {
          capturedUrl = Uri.parse(args.first);
          final cbPort = callbackPortFrom(capturedUrl);
          fireCallback(
            'code=c&state=${stateFrom(capturedUrl)}',
            callbackPort: cbPort,
          );
          return process;
        },
      );

      await flow.execute();

      expect(
        capturedUrl.queryParameters,
        containsPair('state', isNotEmpty),
      );
    });

    test('prefers an IPv6 callback server with dual-stack enabled', () async {
      Object? boundAddress;
      bool? boundV6Only;

      when(
        () => httpClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(jsonEncode(tokenResponse), 200),
      );

      final flow = createFlow(
        processStarter: (command, args) async {
          final url = Uri.parse(args.first);
          final cbPort = callbackPortFrom(url);
          fireCallback(
            'code=c&state=${stateFrom(url)}',
            callbackPort: cbPort,
          );
          return process;
        },
        bindServer:
            (
              address,
              port,
              context, {
              backlog = 0,
              shared = false,
              v6Only = false,
            }) {
              boundAddress = address;
              boundV6Only = v6Only;
              return HttpServer.bindSecure(
                address,
                port,
                context,
                backlog: backlog,
                shared: shared,
                v6Only: v6Only,
              );
            },
      );

      await flow.execute();

      expect(boundAddress, equals(InternetAddress.loopbackIPv6));
      expect(boundV6Only, isFalse);
    });

    test('falls back to IPv4 when IPv6 callback binding fails', () async {
      final bindAttempts = <Object>[];

      when(
        () => httpClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(jsonEncode(tokenResponse), 200),
      );

      final flow = createFlow(
        processStarter: (command, args) async {
          final url = Uri.parse(args.first);
          final cbPort = callbackPortFrom(url);
          fireCallback(
            'code=c&state=${stateFrom(url)}',
            callbackPort: cbPort,
          );
          return process;
        },
        bindServer:
            (
              address,
              port,
              context, {
              backlog = 0,
              shared = false,
              v6Only = false,
            }) {
              bindAttempts.add(address);
              if (address == InternetAddress.loopbackIPv6) {
                throw const SocketException('IPv6 unsupported');
              }

              return HttpServer.bindSecure(
                address,
                port,
                context,
                backlog: backlog,
                shared: shared,
                v6Only: v6Only,
              );
            },
      );

      await flow.execute();

      expect(
        bindAttempts,
        equals([
          InternetAddress.loopbackIPv6,
          InternetAddress.loopbackIPv4,
        ]),
      );
    });

    test(
      'completes successfully with valid code and matching state',
      () async {
        when(
          () => httpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer(
          (_) async => http.Response(jsonEncode(tokenResponse), 200),
        );

        final flow = createFlow(
          processStarter: (command, args) async {
            final url = Uri.parse(args.first);
            final cbPort = callbackPortFrom(url);
            fireCallback(
              'code=auth-code&state=${stateFrom(url)}',
              callbackPort: cbPort,
            );
            return process;
          },
        );

        final credentials = await flow.execute();

        expect(credentials.accessToken, equals('xoxp-test'));
        expect(credentials.userId, equals('U123'));
      },
    );

    test('rejects callback with mismatched state', () async {
      final flow = createFlow(
        processStarter: (command, args) async {
          final url = Uri.parse(args.first);
          final cbPort = callbackPortFrom(url);
          fireCallback('code=c&state=wrong', callbackPort: cbPort);
          return process;
        },
      );

      await expectLater(
        flow.execute(),
        throwsA(
          isA<OAuthException>().having(
            (e) => e.message,
            'message',
            contains('CSRF'),
          ),
        ),
      );
    });

    test('rejects callback with missing state', () async {
      final flow = createFlow(
        processStarter: (command, args) async {
          final url = Uri.parse(args.first);
          final cbPort = callbackPortFrom(url);
          fireCallback('code=c', callbackPort: cbPort);
          return process;
        },
      );

      await expectLater(
        flow.execute(),
        throwsA(
          isA<OAuthException>().having(
            (e) => e.message,
            'message',
            contains('CSRF'),
          ),
        ),
      );
    });

    test('returns error when Slack returns error parameter', () async {
      final flow = createFlow(
        processStarter: (command, args) async {
          final url = Uri.parse(args.first);
          final cbPort = callbackPortFrom(url);
          fireCallback('error=access_denied', callbackPort: cbPort);
          return process;
        },
      );

      await expectLater(
        flow.execute(),
        throwsA(
          isA<OAuthException>().having(
            (e) => e.message,
            'message',
            equals('access_denied'),
          ),
        ),
      );
    });

    test('returns error when code is missing from callback', () async {
      final flow = createFlow(
        processStarter: (command, args) async {
          final url = Uri.parse(args.first);
          final cbPort = callbackPortFrom(url);
          fireCallback(
            'state=${stateFrom(url)}',
            callbackPort: cbPort,
          );
          return process;
        },
      );

      await expectLater(
        flow.execute(),
        throwsA(
          isA<OAuthException>().having(
            (e) => e.message,
            'message',
            contains('Missing authorization code'),
          ),
        ),
      );
    });

    test('escapes HTML special characters in error response', () async {
      final responseFuture = Completer<String>();

      final flow = createFlow(
        processStarter: (command, args) async {
          final url = Uri.parse(args.first);
          final cbPort = callbackPortFrom(url);
          unawaited(
            sendCallback(
              'error=${Uri.encodeComponent('<script>alert(1)</script>')}',
              callbackPort: cbPort,
            ).then(responseFuture.complete).onError((_, _) => ''),
          );
          return process;
        },
      );

      await expectLater(
        flow.execute(),
        throwsA(isA<OAuthException>()),
      );

      final responseBody = await responseFuture.future;
      expect(responseBody, contains('&lt;script&gt;'));
      expect(responseBody, isNot(contains('<script>')));
    });

    test('throws OAuthException when token exchange fails', () async {
      when(
        () => httpClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          jsonEncode({'ok': false, 'error': 'invalid_code'}),
          200,
        ),
      );

      final flow = createFlow(
        processStarter: (command, args) async {
          final url = Uri.parse(args.first);
          final cbPort = callbackPortFrom(url);
          fireCallback(
            'code=bad&state=${stateFrom(url)}',
            callbackPort: cbPort,
          );
          return process;
        },
      );

      await expectLater(
        flow.execute(),
        throwsA(
          isA<OAuthException>().having(
            (e) => e.message,
            'message',
            contains('invalid_code'),
          ),
        ),
      );
    });

    test('generates cert and key files in config directory', () async {
      when(
        () => httpClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(jsonEncode(tokenResponse), 200),
      );

      final flow = createFlow(
        processStarter: (command, args) async {
          final url = Uri.parse(args.first);
          final cbPort = callbackPortFrom(url);
          fireCallback(
            'code=c&state=${stateFrom(url)}',
            callbackPort: cbPort,
          );
          return process;
        },
      );

      await flow.execute();

      expect(File('${tempDir.path}/cert.pem').existsSync(), isTrue);
      expect(File('${tempDir.path}/key.pem').existsSync(), isTrue);
    });

    test('reuses existing cert and key files', () async {
      when(
        () => httpClient.post(
          any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => http.Response(jsonEncode(tokenResponse), 200),
      );

      // First run generates certs.
      var flow = createFlow(
        processStarter: (command, args) async {
          final url = Uri.parse(args.first);
          final cbPort = callbackPortFrom(url);
          fireCallback(
            'code=c&state=${stateFrom(url)}',
            callbackPort: cbPort,
          );
          return process;
        },
      );
      await flow.execute();

      final certModified = File('${tempDir.path}/cert.pem').lastModifiedSync();
      final keyModified = File('${tempDir.path}/key.pem').lastModifiedSync();

      // Second run — certs should not be regenerated.
      flow = createFlow(
        processStarter: (command, args) async {
          final url = Uri.parse(args.first);
          final cbPort = callbackPortFrom(url);
          fireCallback(
            'code=c&state=${stateFrom(url)}',
            callbackPort: cbPort,
          );
          return process;
        },
      );
      await flow.execute();

      expect(
        File('${tempDir.path}/cert.pem').lastModifiedSync(),
        equals(certModified),
      );
      expect(
        File('${tempDir.path}/key.pem').lastModifiedSync(),
        equals(keyModified),
      );
    });
  });
}
