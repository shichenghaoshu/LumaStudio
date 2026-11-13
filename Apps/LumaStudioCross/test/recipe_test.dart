import 'package:flutter_test/flutter_test.dart';
import 'package:lumastudio/recipe.dart';

void main() {
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
