import 'package:flutter_test/flutter_test.dart';
import 'package:wfform/shared/platform.dart';

import '../presentation/studio_test.dart' as fixtures;

void main() {
  test(
    'sidebar preference restores finite bounds and safely ignores invalid data',
    () {
      for (final entry in {
        null: 290.0,
        'not a width': 290.0,
        'NaN': 290.0,
        'Infinity': 290.0,
        '-Infinity': 290.0,
        '100': 240.0,
        '1000': 440.0,
        '352.5': 352.5,
      }.entries) {
        final memory = MemoryStore();
        if (entry.key != null) {
          memory.write('freeform.sidebarWidth', entry.key!);
        }
        final h = fixtures.Harness(memory: memory);
        expect(h.state.sidebarWidth, entry.value, reason: '${entry.key}');
        h.state.dispose();
      }
    },
  );

  test(
    'sidebar changes persist only on actual finite changes without appearance rebuilds',
    () {
      final h = fixtures.Harness();
      addTearDown(h.state.dispose);
      var changes = 0;
      var appearanceChanges = 0;
      h.state.addListener(() => changes++);
      h.state.appearance.addListener(() => appearanceChanges++);
      h.state.setSidebarWidth(360);
      expect(h.state.sidebarWidth, 360);
      expect(h.store.read('freeform.sidebarWidth'), '360.0');
      h.state.setSidebarWidth(360);
      h.state.setSidebarWidth(double.nan);
      h.state.setSidebarWidth(double.infinity);
      expect(changes, 1);
      h.state.setSidebarWidth(10000);
      expect(h.state.sidebarWidth, 440);
      expect(changes, 2);
      expect(appearanceChanges, 0);
      final restored = fixtures.Harness(memory: h.store);
      addTearDown(restored.state.dispose);
      expect(restored.state.sidebarWidth, 440);
    },
  );

  test(
    'collapse persists independently and an action restores the default width',
    () {
      final h = fixtures.Harness();
      addTearDown(h.state.dispose);
      h.state.setSidebarWidth(400);
      h.state.collapseSidebar();
      expect(h.state.sidebarCollapsed, isTrue);
      expect(h.state.sidebarWidth, 400);
      final restored = fixtures.Harness(memory: h.store);
      addTearDown(restored.state.dispose);
      expect(restored.state.sidebarCollapsed, isTrue);
      expect(restored.state.sidebarWidth, 400);
      var changes = 0;
      restored.state.addListener(() => changes++);
      restored.state.restoreSidebar();
      expect(restored.state.sidebarCollapsed, isFalse);
      expect(restored.state.sidebarWidth, 290);
      expect(h.store.read('freeform.sidebarCollapsed'), 'false');
      expect(h.store.read('freeform.sidebarWidth'), '290.0');
      restored.state.restoreSidebar();
      expect(changes, 1);
    },
  );
}
