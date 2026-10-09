import 'package:flutter_test/flutter_test.dart';
import 'package:wfform/shared/platform.dart';

void main() {
  test('phones and tablets are excluded including desktop-mode iPad', () {
    for (final device in [
      ('Mozilla/5.0 (Linux; Android 14; Pixel 9) Mobile', 'Linux armv8l', 5),
      (
        'Mozilla/5.0 (Linux; Android 14; Tablet) AppleWebKit/537',
        'Linux armv8l',
        5,
      ),
      ('Mozilla/5.0 (iPhone; CPU iPhone OS 18)', 'iPhone', 5),
      ('Mozilla/5.0 (iPad; CPU OS 18)', 'iPad', 5),
      (
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15) Version/18 Safari',
        'MacIntel',
        5,
      ),
      ('Mozilla/5.0 Silk/80 Kindle Fire', 'Linux armv7l', 5),
    ]) {
      expect(
        browserSupportsTools(
          userAgent: device.$1,
          platform: device.$2,
          maxTouchPoints: device.$3,
        ),
        false,
        reason: device.$1,
      );
    }
  });
  test('desktop-mode Android tablet remains disabled with touch-only input', () {
    expect(
      browserSupportsTools(
        userAgent:
            'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/119.0.0.0 Safari/537.36',
        platform: 'Linux x86_64',
        maxTouchPoints: 5,
        primaryPointerCoarse: true,
        anyFinePointer: false,
      ),
      false,
    );
  });
  test('touch laptops retain tools when a fine pointer is available', () {
    for (final coarse in [false, true]) {
      expect(
        browserSupportsTools(
          userAgent: 'Mozilla/5.0 (X11; Linux x86_64)',
          platform: 'Linux x86_64',
          maxTouchPoints: 10,
          primaryPointerCoarse: coarse,
          anyFinePointer: true,
        ),
        true,
      );
    }
  });
  test('coarse pointer alone does not exclude a computer without touch', () {
    expect(
      browserSupportsTools(
        userAgent: 'Mozilla/5.0 (X11; Linux x86_64)',
        platform: 'Linux x86_64',
        maxTouchPoints: 0,
        primaryPointerCoarse: true,
        anyFinePointer: false,
      ),
      true,
    );
  });
  test(
    'desktop PCs and touch laptops keep tools independently of window size',
    () {
      for (final device in [
        ('Mozilla/5.0 (X11; Linux x86_64)', 'Linux x86_64', 0),
        ('Mozilla/5.0 (Windows NT 10.0; Win64; x64)', 'Win32', 10),
        ('Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15)', 'MacIntel', 0),
        ('Mozilla/5.0 (X11; CrOS x86_64)', 'Linux x86_64', 10),
      ]) {
        expect(
          browserSupportsTools(
            userAgent: device.$1,
            platform: device.$2,
            maxTouchPoints: device.$3,
          ),
          true,
          reason: device.$1,
        );
      }
    },
  );
}
