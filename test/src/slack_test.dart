import 'dart:convert';
import 'dart:io';

import 'package:dart_slack/src/slack.dart';
import 'package:dart_slack/src/slack_api/slack_urls.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockHttpClient extends Mock implements http.Client {}

void main() {
  group('Slack', () {
    late http.Client httpClient;
    late Slack slack;

    setUp(() {
      httpClient = _MockHttpClient();
      slack = Slack(token: 'xoxp-test', httpClient: httpClient);
    });

    setUpAll(() {
      registerFallbackValue(Uri.parse('https://example.com'));
      registerFallbackValue(
        http.Request('GET', Uri.parse('https://example.com')),
      );
    });

    group('uploadFile', () {
      test(
        'drives the get-upload-url / upload / complete flow and returns '
        'the filename',
        () async {
          final tempFile = File(
            '${Directory.systemTemp.path}/dart_slack_upload_test.txt',
          )..writeAsStringSync('hello world');
          addTearDown(tempFile.deleteSync);

          when(
            () => httpClient.get(any(), headers: any(named: 'headers')),
          ).thenAnswer(
            (_) async => http.Response(
              jsonEncode({
                'ok': true,
                'upload_url': 'https://files.slack.com/upload/v1/abc',
                'file_id': 'F123',
              }),
              200,
            ),
          );
          when(() => httpClient.send(any())).thenAnswer(
            (_) async => http.StreamedResponse(
              Stream.value(utf8.encode('OK')),
              200,
            ),
          );
          when(
            () => httpClient.post(
              any(),
              headers: any(named: 'headers'),
              body: any(named: 'body'),
            ),
          ).thenAnswer(
            (_) async => http.Response(
              jsonEncode({'ok': true, 'files': <Map<String, dynamic>>[]}),
              200,
            ),
          );

          final filename = await slack.uploadFile(
            channel: 'C1',
            path: tempFile.path,
            threadTs: '1.0',
            comment: 'here you go',
          );

          expect(filename, equals('dart_slack_upload_test.txt'));

          final uploadRequest =
              verify(() => httpClient.send(captureAny())).captured.single
                  as http.MultipartRequest;
          expect(
            uploadRequest.url,
            equals(Uri.parse('https://files.slack.com/upload/v1/abc')),
          );

          final completeBody =
              jsonDecode(
                    verify(
                          () => httpClient.post(
                            captureAny(),
                            headers: any(named: 'headers'),
                            body: captureAny(named: 'body'),
                          ),
                        ).captured[1]
                        as String,
                  )
                  as Map<String, dynamic>;
          final files = (completeBody['files'] as List<dynamic>)
              .cast<Map<String, dynamic>>();
          expect(files.single['id'], equals('F123'));
          expect(completeBody['channel_id'], equals('C1'));
          expect(completeBody['thread_ts'], equals('1.0'));
          expect(completeBody['initial_comment'], equals('here you go'));
        },
      );
    });

    group('openDirectMessage', () {
      test('returns the resolved DM channel ID', () async {
        when(
          () => httpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer(
          (_) async => http.Response(
            jsonEncode({
              'ok': true,
              'channel': {'id': 'D1'},
            }),
            200,
          ),
        );

        final channel = await slack.openDirectMessage(user: 'U9');

        expect(channel, equals('D1'));
      });
    });

    group('postMessage', () {
      test('returns a typed SlackMessage', () async {
        when(
          () => httpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer(
          (_) async => http.Response(
            jsonEncode({
              'ok': true,
              'channel': 'C123',
              'ts': '111.222',
              'message': {'text': 'Hi', 'ts': '111.222'},
            }),
            200,
          ),
        );

        final msg = await slack.postMessage(
          channel: 'C123',
          text: 'Hi',
        );

        expect(msg.channel, equals('C123'));
        expect(msg.ts, equals('111.222'));
        expect(msg.text, equals('Hi'));
      });
    });

    group('listChannels', () {
      test('returns typed SlackChannel list', () async {
        when(
          () => httpClient.get(
            any(),
            headers: any(named: 'headers'),
          ),
        ).thenAnswer(
          (_) async => http.Response(
            jsonEncode({
              'ok': true,
              'channels': [
                {'id': 'C1', 'name': 'general', 'is_private': false},
                {'id': 'G2', 'name': 'secret', 'is_private': true},
              ],
            }),
            200,
          ),
        );

        final channels = await slack.listChannels();

        expect(channels, hasLength(2));
        expect(channels[0].id, equals('C1'));
        expect(channels[0].name, equals('general'));
        expect(channels[0].isPrivate, isFalse);
        expect(channels[1].id, equals('G2'));
        expect(channels[1].isPrivate, isTrue);
      });

      test('aggregates paginated channel responses', () async {
        var callCount = 0;
        when(
          () => httpClient.get(
            any(),
            headers: any(named: 'headers'),
          ),
        ).thenAnswer(
          (_) async {
            callCount++;
            return http.Response(
              jsonEncode({
                'ok': true,
                'channels': [
                  if (callCount == 1)
                    {'id': 'C1', 'name': 'general', 'is_private': false}
                  else
                    {'id': 'G2', 'name': 'secret', 'is_private': true},
                ],
                'response_metadata': {
                  'next_cursor': callCount == 1 ? 'cursor-1' : '',
                },
              }),
              200,
            );
          },
        );

        final channels = await slack.listChannels();

        expect(channels, hasLength(2));
        expect(channels[0].id, equals('C1'));
        expect(channels[1].id, equals('G2'));
      });
    });

    group('joinChannel', () {
      test('delegates to the underlying client', () async {
        when(
          () => httpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer(
          (_) async => http.Response(
            jsonEncode({'ok': true}),
            200,
          ),
        );

        await slack.joinChannel('C123');

        final captured = verify(
          () => httpClient.post(
            captureAny(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).captured;

        expect(captured[0] as Uri, equals(SlackUrls.conversationsJoin));
      });
    });

    group('updateMessage', () {
      test('returns a typed SlackMessage', () async {
        when(
          () => httpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer(
          (_) async => http.Response(
            jsonEncode({
              'ok': true,
              'channel': 'C1',
              'ts': '1.0',
              'message': {'text': 'updated'},
            }),
            200,
          ),
        );

        final msg = await slack.updateMessage(
          channel: 'C1',
          ts: '1.0',
          text: 'updated',
        );

        expect(msg.channel, equals('C1'));
        expect(msg.text, equals('updated'));
      });
    });

    group('deleteMessage', () {
      test('completes without error', () async {
        when(
          () => httpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer(
          (_) async => http.Response(
            jsonEncode({'ok': true, 'channel': 'C1', 'ts': '1.0'}),
            200,
          ),
        );

        await slack.deleteMessage(channel: 'C1', ts: '1.0');

        verify(
          () => httpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).called(1);
      });
    });

    group('conversationsHistory', () {
      test('returns CursorPage of SlackMessage', () async {
        when(
          () => httpClient.get(any(), headers: any(named: 'headers')),
        ).thenAnswer(
          (_) async => http.Response(
            jsonEncode({
              'ok': true,
              'messages': [
                {'ts': '2.0', 'text': 'second', 'user': 'U1'},
                {'ts': '1.0', 'text': 'first', 'user': 'U2'},
              ],
              'has_more': true,
              'response_metadata': {'next_cursor': 'abc123'},
            }),
            200,
          ),
        );

        final page = await slack.conversationsHistory(channel: 'C1');

        expect(page.items, hasLength(2));
        expect(page.items[0].text, equals('second'));
        expect(page.items[0].user, equals('U1'));
        expect(page.hasMore, isTrue);
        expect(page.nextCursor, equals('abc123'));
      });

      test('treats empty cursor as null', () async {
        when(
          () => httpClient.get(any(), headers: any(named: 'headers')),
        ).thenAnswer(
          (_) async => http.Response(
            jsonEncode({
              'ok': true,
              'messages': <Map<String, dynamic>>[],
              'has_more': false,
              'response_metadata': {'next_cursor': ''},
            }),
            200,
          ),
        );

        final page = await slack.conversationsHistory(channel: 'C1');

        expect(page.nextCursor, isNull);
      });
    });

    group('conversationsReplies', () {
      test('returns CursorPage of SlackMessage', () async {
        when(
          () => httpClient.get(any(), headers: any(named: 'headers')),
        ).thenAnswer(
          (_) async => http.Response(
            jsonEncode({
              'ok': true,
              'messages': [
                {'ts': '1.0', 'text': 'parent', 'user': 'U1'},
                {'ts': '1.1', 'text': 'reply', 'user': 'U2'},
              ],
              'has_more': false,
            }),
            200,
          ),
        );

        final page = await slack.conversationsReplies(
          channel: 'C1',
          ts: '1.0',
        );

        expect(page.items, hasLength(2));
        expect(page.items[1].text, equals('reply'));
        expect(page.hasMore, isFalse);
      });
    });

    group('conversationsInfo', () {
      test('returns a typed SlackChannel', () async {
        when(
          () => httpClient.get(any(), headers: any(named: 'headers')),
        ).thenAnswer(
          (_) async => http.Response(
            jsonEncode({
              'ok': true,
              'channel': {
                'id': 'C1',
                'name': 'general',
                'is_private': false,
                'topic': {'value': 'Announcements'},
                'purpose': {'value': 'General chat'},
                'num_members': 42,
                'is_archived': false,
              },
            }),
            200,
          ),
        );

        final channel = await slack.conversationsInfo(channel: 'C1');

        expect(channel.id, equals('C1'));
        expect(channel.name, equals('general'));
        expect(channel.topic, equals('Announcements'));
        expect(channel.purpose, equals('General chat'));
        expect(channel.memberCount, equals(42));
      });
    });

    group('conversationsMembers', () {
      test('returns CursorPage of String', () async {
        when(
          () => httpClient.get(any(), headers: any(named: 'headers')),
        ).thenAnswer(
          (_) async => http.Response(
            jsonEncode({
              'ok': true,
              'members': ['U1', 'U2', 'U3'],
              'response_metadata': {'next_cursor': 'xyz'},
            }),
            200,
          ),
        );

        final page = await slack.conversationsMembers(channel: 'C1');

        expect(page.items, equals(['U1', 'U2', 'U3']));
        expect(page.hasMore, isTrue);
        expect(page.nextCursor, equals('xyz'));
      });
    });

    group('usersList', () {
      test('returns CursorPage of SlackUser', () async {
        when(
          () => httpClient.get(any(), headers: any(named: 'headers')),
        ).thenAnswer(
          (_) async => http.Response(
            jsonEncode({
              'ok': true,
              'members': [
                {
                  'id': 'U1',
                  'name': 'jane',
                  'real_name': 'Jane Doe',
                  'is_bot': false,
                  'deleted': false,
                  'profile': {'display_name': 'Jane'},
                },
              ],
              'response_metadata': {'next_cursor': ''},
            }),
            200,
          ),
        );

        final page = await slack.usersList();

        expect(page.items, hasLength(1));
        expect(page.items[0].id, equals('U1'));
        expect(page.items[0].realName, equals('Jane Doe'));
        expect(page.hasMore, isFalse);
      });
    });

    group('usersInfo', () {
      test('returns a typed SlackUser', () async {
        when(
          () => httpClient.get(any(), headers: any(named: 'headers')),
        ).thenAnswer(
          (_) async => http.Response(
            jsonEncode({
              'ok': true,
              'user': {
                'id': 'U1',
                'name': 'jane',
                'real_name': 'Jane Doe',
                'is_bot': false,
                'deleted': false,
                'profile': {
                  'display_name': 'Jane',
                  'email': 'jane@example.com',
                },
              },
            }),
            200,
          ),
        );

        final user = await slack.usersInfo(user: 'U1');

        expect(user.id, equals('U1'));
        expect(user.realName, equals('Jane Doe'));
        expect(user.email, equals('jane@example.com'));
      });
    });

    group('createCanvas', () {
      test('returns the new canvas ID', () async {
        when(
          () => httpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer(
          (_) async => http.Response(
            jsonEncode({'ok': true, 'canvas_id': 'F123'}),
            200,
          ),
        );

        final id = await slack.createCanvas(markdown: '# Hi', title: 'Doc');

        expect(id, equals('F123'));
      });
    });

    group('readCanvas', () {
      test('downloads the body from the file url_private_download', () async {
        when(
          () => httpClient.get(any(), headers: any(named: 'headers')),
        ).thenAnswer((invocation) async {
          final uri = invocation.positionalArguments.first as Uri;
          if (uri.path.contains('files.info')) {
            return http.Response(
              jsonEncode({
                'ok': true,
                'file': {
                  'id': 'F1',
                  'filetype': 'canvas',
                  'url_private_download': 'https://files.slack.com/c-F1',
                },
              }),
              200,
            );
          }
          return http.Response('# Notes', 200);
        });

        final content = await slack.readCanvas(canvasId: 'F1');

        expect(content, equals('# Notes'));
      });

      test('returns null when the file has no download URL', () async {
        when(
          () => httpClient.get(any(), headers: any(named: 'headers')),
        ).thenAnswer(
          (_) async => http.Response(
            jsonEncode({
              'ok': true,
              'file': {'id': 'F1', 'filetype': 'png'},
            }),
            200,
          ),
        );

        final content = await slack.readCanvas(canvasId: 'F1');

        expect(content, isNull);
      });

      test(
        'returns null without downloading a non-canvas file that has a URL',
        () async {
          var downloadAttempted = false;
          when(
            () => httpClient.get(any(), headers: any(named: 'headers')),
          ).thenAnswer((invocation) async {
            final uri = invocation.positionalArguments.first as Uri;
            if (uri.path.contains('files.info')) {
              return http.Response(
                jsonEncode({
                  'ok': true,
                  'file': {
                    'id': 'F1',
                    'filetype': 'png',
                    'pretty_type': 'PNG',
                    'url_private_download': 'https://files.slack.com/c-F1',
                    'url_private': 'https://files.slack.com/p-F1',
                  },
                }),
                200,
              );
            }
            downloadAttempted = true;
            return http.Response('binary', 200);
          });

          final content = await slack.readCanvas(canvasId: 'F1');

          expect(content, isNull);
          expect(
            downloadAttempted,
            isFalse,
            reason: 'a non-canvas file must not be downloaded',
          );
        },
      );

      test('reads a legacy quip-filetype canvas', () async {
        when(
          () => httpClient.get(any(), headers: any(named: 'headers')),
        ).thenAnswer((invocation) async {
          final uri = invocation.positionalArguments.first as Uri;
          if (uri.path.contains('files.info')) {
            return http.Response(
              jsonEncode({
                'ok': true,
                'file': {
                  'id': 'F1',
                  'filetype': 'quip',
                  'url_private_download': 'https://files.slack.com/c-F1',
                },
              }),
              200,
            );
          }
          return http.Response('# Notes', 200);
        });

        final content = await slack.readCanvas(canvasId: 'F1');

        expect(content, equals('# Notes'));
      });

      test(
        'falls back to url_private when no download URL is present',
        () async {
          Uri? downloadUri;
          when(
            () => httpClient.get(any(), headers: any(named: 'headers')),
          ).thenAnswer((invocation) async {
            final uri = invocation.positionalArguments.first as Uri;
            if (uri.path.contains('files.info')) {
              return http.Response(
                jsonEncode({
                  'ok': true,
                  'file': {
                    'id': 'F1',
                    'filetype': 'canvas',
                    'url_private': 'https://files.slack.com/p-F1',
                  },
                }),
                200,
              );
            }
            downloadUri = uri;
            return http.Response('# Notes', 200);
          });

          final content = await slack.readCanvas(canvasId: 'F1');

          expect(content, equals('# Notes'));
          expect(
            downloadUri,
            equals(Uri.parse('https://files.slack.com/p-F1')),
          );
        },
      );

      test('reads a canvas identified by pretty_type', () async {
        when(
          () => httpClient.get(any(), headers: any(named: 'headers')),
        ).thenAnswer((invocation) async {
          final uri = invocation.positionalArguments.first as Uri;
          if (uri.path.contains('files.info')) {
            return http.Response(
              jsonEncode({
                'ok': true,
                'file': {
                  'id': 'F1',
                  'pretty_type': 'Canvas',
                  'url_private_download': 'https://files.slack.com/c-F1',
                },
              }),
              200,
            );
          }
          return http.Response('# Notes', 200);
        });

        final content = await slack.readCanvas(canvasId: 'F1');

        expect(content, equals('# Notes'));
      });

      test('reads a channel canvas identified by mode', () async {
        when(
          () => httpClient.get(any(), headers: any(named: 'headers')),
        ).thenAnswer((invocation) async {
          final uri = invocation.positionalArguments.first as Uri;
          if (uri.path.contains('files.info')) {
            return http.Response(
              jsonEncode({
                'ok': true,
                'file': {
                  'id': 'F1',
                  'mode': 'canvas',
                  'url_private_download': 'https://files.slack.com/c-F1',
                },
              }),
              200,
            );
          }
          return http.Response('# Notes', 200);
        });

        final content = await slack.readCanvas(canvasId: 'F1');

        expect(content, equals('# Notes'));
      });

      test(
        'returns null without downloading when the URL host is not Slack',
        () async {
          var downloadAttempted = false;
          when(
            () => httpClient.get(any(), headers: any(named: 'headers')),
          ).thenAnswer((invocation) async {
            final uri = invocation.positionalArguments.first as Uri;
            if (uri.path.contains('files.info')) {
              return http.Response(
                jsonEncode({
                  'ok': true,
                  'file': {
                    'id': 'F1',
                    'filetype': 'canvas',
                    'url_private_download': 'https://evil.example.com/c-F1',
                  },
                }),
                200,
              );
            }
            downloadAttempted = true;
            return http.Response('# Notes', 200);
          });

          final content = await slack.readCanvas(canvasId: 'F1');

          expect(content, isNull);
          expect(
            downloadAttempted,
            isFalse,
            reason: 'the bearer token must not be sent to a non-Slack host',
          );
        },
      );

      test(
        'returns null without downloading when the URL is not HTTPS',
        () async {
          var downloadAttempted = false;
          when(
            () => httpClient.get(any(), headers: any(named: 'headers')),
          ).thenAnswer((invocation) async {
            final uri = invocation.positionalArguments.first as Uri;
            if (uri.path.contains('files.info')) {
              return http.Response(
                jsonEncode({
                  'ok': true,
                  'file': {
                    'id': 'F1',
                    'filetype': 'canvas',
                    'url_private_download': 'http://files.slack.com/c-F1',
                  },
                }),
                200,
              );
            }
            downloadAttempted = true;
            return http.Response('# Notes', 200);
          });

          final content = await slack.readCanvas(canvasId: 'F1');

          expect(content, isNull);
          expect(
            downloadAttempted,
            isFalse,
            reason: 'the bearer token must not be sent over plaintext HTTP',
          );
        },
      );

      test(
        'returns null when the download answers a 200 HTML login page',
        () async {
          when(
            () => httpClient.get(any(), headers: any(named: 'headers')),
          ).thenAnswer((invocation) async {
            final uri = invocation.positionalArguments.first as Uri;
            if (uri.path.contains('files.info')) {
              return http.Response(
                jsonEncode({
                  'ok': true,
                  'file': {
                    'id': 'F1',
                    'filetype': 'canvas',
                    'url_private_download': 'https://files.slack.com/c-F1',
                  },
                }),
                200,
              );
            }
            return http.Response(
              '<!doctype html><html><body>Sign in to Slack</body></html>',
              200,
              headers: {'content-type': 'text/html; charset=utf-8'},
            );
          });

          final content = await slack.readCanvas(canvasId: 'F1');

          expect(
            content,
            isNull,
            reason: 'an HTML sign-in page is not canvas content',
          );
        },
      );
    });

    group('editCanvas', () {
      test('maps the append mode to insert_at_end', () async {
        when(
          () => httpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer(
          (_) async => http.Response(jsonEncode({'ok': true}), 200),
        );

        await slack.editCanvas(
          canvasId: 'F1',
          markdown: 'more',
          mode: CanvasEditMode.append,
        );

        final body =
            jsonDecode(
                  verify(
                        () => httpClient.post(
                          any(),
                          headers: any(named: 'headers'),
                          body: captureAny(named: 'body'),
                        ),
                      ).captured.first
                      as String,
                )
                as Map<String, dynamic>;
        final change =
            (body['changes'] as List<dynamic>).first as Map<String, dynamic>;

        expect(body['canvas_id'], equals('F1'));
        expect(change['operation'], equals('insert_at_end'));
        expect(
          (change['document_content'] as Map<String, dynamic>)['markdown'],
          equals('more'),
        );
      });
    });

    group('deleteCanvas', () {
      test('posts the canvas ID', () async {
        when(
          () => httpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer(
          (_) async => http.Response(jsonEncode({'ok': true}), 200),
        );

        await slack.deleteCanvas(canvasId: 'F1');

        final body =
            jsonDecode(
                  verify(
                        () => httpClient.post(
                          any(),
                          headers: any(named: 'headers'),
                          body: captureAny(named: 'body'),
                        ),
                      ).captured.first
                      as String,
                )
                as Map<String, dynamic>;

        expect(body['canvas_id'], equals('F1'));
      });
    });

    group('CanvasEditMode', () {
      test('fromName maps known values and defaults to replace', () {
        expect(CanvasEditMode.fromName('append'), CanvasEditMode.append);
        expect(CanvasEditMode.fromName('prepend'), CanvasEditMode.prepend);
        expect(CanvasEditMode.fromName('replace'), CanvasEditMode.replace);
        expect(CanvasEditMode.fromName(null), CanvasEditMode.replace);
        expect(CanvasEditMode.fromName('bogus'), CanvasEditMode.replace);
      });
    });

    group('setStatus', () {
      test('posts the status profile to users.profile.set', () async {
        when(
          () => httpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer(
          (_) async => http.Response(jsonEncode({'ok': true}), 200),
        );

        await slack.setStatus(
          text: 'On a task',
          emoji: ':gear:',
          expiration: 1750000000,
        );

        final captured = verify(
          () => httpClient.post(
            captureAny(),
            headers: any(named: 'headers'),
            body: captureAny(named: 'body'),
          ),
        ).captured;

        expect(captured[0], equals(SlackUrls.usersProfileSet));
        final body = jsonDecode(captured[1] as String) as Map<String, dynamic>;
        final profile = body['profile'] as Map<String, dynamic>;
        expect(profile['status_text'], equals('On a task'));
        expect(profile['status_emoji'], equals(':gear:'));
        expect(profile['status_expiration'], equals(1750000000));
      });
    });

    group('clearStatus', () {
      test('posts an empty status profile', () async {
        when(
          () => httpClient.post(
            any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          ),
        ).thenAnswer(
          (_) async => http.Response(jsonEncode({'ok': true}), 200),
        );

        await slack.clearStatus();

        final captured = verify(
          () => httpClient.post(
            captureAny(),
            headers: any(named: 'headers'),
            body: captureAny(named: 'body'),
          ),
        ).captured;

        expect(captured[0], equals(SlackUrls.usersProfileSet));
        final body = jsonDecode(captured[1] as String) as Map<String, dynamic>;
        final profile = body['profile'] as Map<String, dynamic>;
        expect(profile['status_text'], isEmpty);
        expect(profile['status_emoji'], isEmpty);
        expect(profile['status_expiration'], equals(0));
      });
    });

    test('close delegates to the underlying client', () {
      when(() => httpClient.close()).thenReturn(null);
      slack.close();
      verify(() => httpClient.close()).called(1);
    });
  });
}
