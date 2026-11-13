import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lumastudio/studio.dart';
import 'package:lumastudio/recipe.dart';

void main() {
  Studio fixture() {
    final s = Studio();
    s.current = Photo(
      id: 'fixture',
      name: 'fixture',
      path: 'unused',
      thumbnail: 'unused',
    );
    s.apiKey = 'fixture-token';
    s.recipe = Recipe().set(0, .3);
    return s;
  }

  test(
    'HTTP failures preserve manual edits and send no photo payload',
    () async {
      final s = fixture(), old = s.recipe;
      try {
        final client = MockClient((request) async {
          expect(request.headers['authorization'], 'Bearer fixture-token');
          expect(request.followRedirects, isFalse);
          final body = jsonDecode(request.body);
          expect(body['messages'][1]['content'], '提亮一点');
          expect(request.body.contains('image_url'), isFalse);
          return http.Response('unavailable', 503);
        });
        await expectLater(
          s.runAgent('提亮一点', transport: client),
          throwsStateError,
        );
        expect(s.recipe, old);
        expect(s.undoStack, isEmpty);
        expect(s.agentBusy, isFalse);
      } finally {
        s.dispose();
      }
    },
  );
  test('cancelled online request cannot later commit a recipe', () async {
    final s = fixture(),
        old = s.recipe,
        ready = Completer<http.Response>(),
        sent = Completer<void>();
    try {
      final client = MockClient((request) {
        sent.complete();
        return ready.future;
      });
      final pending = s.runAgent('曝光增加一档', transport: client);
      await sent.future;
      s.cancelAgent();
      ready.complete(
        http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': jsonEncode({
                    'changes': {'exposure': 1.0},
                  }),
                },
              },
            ],
          }),
          200,
        ),
      );
      await pending;
      expect(s.recipe, old);
      expect(s.undoStack, isEmpty);
      expect(s.agentBusy, isFalse);
    } finally {
      s.dispose();
    }
  });
}
