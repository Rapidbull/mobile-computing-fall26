import 'package:flutter_test/flutter_test.dart';
import 'package:split_tracker/main.dart';

void main() {
  test('Split time formatter handles minutes and hours', () {
    expect(formatTime(90.5), '1:30.50');
    expect(formatTime(3601.25), '1:00:01.25');
  });

  test('All supported race distances remain available', () {
    expect(RaceAppModel.distanceMeters['5K'], 5000);
    expect(RaceAppModel.distanceMeters['8K'], 8000);
    expect(RaceAppModel.distanceMeters.containsKey('Marathon'), isTrue);
  });
}
