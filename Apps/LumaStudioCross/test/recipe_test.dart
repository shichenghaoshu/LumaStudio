import 'package:flutter_test/flutter_test.dart';
import 'package:lumastudio/recipe.dart';

void main() {
  test(
    'strong beauty styles preserve unrelated edits and all controls roundtrip',
    () {
      final original = Recipe().set(0, .6).setHSL(3, .2).copy(filter: 'warm');
      for (final style in beautyStyles) {
        final edited = beautyStyle(original, style);
        expect(edited.values[0], .6);
        expect(edited.hsl, original.hsl);
        expect(edited.filter, 'warm');
        expect(Recipe.fromJson(edited.toJson()), edited);
      }
      expect(controls.length + 24, 48);
      final strong = beautyStyle(original, '高强度');
      expect(strong.values[16], 1);
      expect(strong.values[18], 0);
      expect(strong.values[22], greaterThan(.5));
      final limited = applyOnlineProposal(original, {
        'changes': {'skinWhiten': .8, 'skinSmooth': .9},
      }, '重度磨皮，但不要美白');
      expect(limited.values[16], .9);
      expect(limited.values[22], 0);
    },
  );
  test(
    'online proposals preserve unmentioned edits and honor skin exclusions',
    () {
      final old = Recipe().set(11, .7).copy(filter: 'film');
      final proposal = {
        'changes': {'exposure': .4, 'skinSmooth': .8},
      };
      final next = applyOnlineProposal(old, proposal, '提亮一点，不要美颜');
      expect(next.values[0], .4);
      expect(next.values[11], .7);
      expect(next.values[16], 0);
      expect(next.filter, 'film');
      expect(
        applyOnlineProposal(
          old,
          proposal,
          'lighten, do not smooth skin',
        ).values[16],
        0,
      );
      expect(applyOnlineProposal(old, proposal, '磨皮自然一点').values[16], .8);
      expect(applyOnlineProposal(old, {'filter': null}, '移除滤镜').filter, isNull);
      expect(
        () => applyOnlineProposal(old, {
          'changes': {'exposure': 50},
        }, '提亮'),
        throwsFormatException,
      );
      expect(
        () => applyOnlineProposal(old, {'shell': 'bad'}, '提亮'),
        throwsFormatException,
      );
    },
  );
  test('recipe roundtrip retains HSL, geometry and registered preset', () {
    final r = Recipe()
        .set(0, .4)
        .setHSL(4, .35)
        .copy(filter: 'film', turns: 1, aspect: .8, flip: true);
    expect(Recipe.fromJson(r.toJson()), r);
  });
  test('malformed, unknown and unsafe parameters are rejected', () {
    for (final value in [double.nan, 6.0, -6.0]) {
      final j = Recipe().toJson();
      j['values'] = {'exposure': value};
      expect(() => Recipe.fromJson(j), throwsFormatException);
    }
    expect(
      () => Recipe.fromJson({
        'schema': 'luma.portable/v1',
        'values': {'shell': 1},
      }),
      throwsFormatException,
    );
    expect(
      () => Recipe.fromJson({
        'version': 2,
        'global': {'exposure': .5},
      }),
      throwsFormatException,
    );
    final j = Recipe().toJson();
    j['hsl'] = [0];
    expect(() => Recipe.fromJson(j), throwsFormatException);
  });
}
