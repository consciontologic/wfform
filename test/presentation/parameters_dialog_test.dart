import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wfform/features/models/model.dart';
import 'package:wfform/features/documents/document_view.dart';
import 'package:wfform/presentation/parameters_dialog.dart';

const fixture = FreeModel(
  id: 'fixture/model:free',
  name: 'Parameter fixture',
  supportedParameters: ['temperature', 'logprobs', 'reasoning_effort', 'stop'],
);

Future<void> open(
  WidgetTester tester, {
  FreeModel model = fixture,
  Map<String, dynamic> overrides = const {},
  required ValueChanged<Map<String, dynamic>> onApply,
  double scale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => unawaited(
              openParameters(
                context,
                model: model,
                overrides: overrides,
                onApply: onApply,
              ),
            ),
            child: const Text('Open parameters'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open parameters'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'mobile tool parameters remain inert without blocking other settings',
    (tester) async {
      Map<String, dynamic>? applied;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ParametersDialog(
              model: const FreeModel(
                id: 'tools',
                name: 'Tools',
                supportedParameters: [
                  'tools',
                  'tool_choice',
                  'parallel_tool_calls',
                  'temperature',
                ],
              ),
              toolsAvailable: false,
              overrides: const {
                'tool_choice': 'required',
                'parallel_tool_calls': true,
                'temperature': .2,
              },
              onApply: (value) => applied = value,
            ),
          ),
        ),
      );
      expect(
        find.byKey(const Key('parameter-enable-tool_choice')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('parameter-enable-parallel_tool_calls')),
        findsNothing,
      );
      expect(
        find.textContaining('Tools are available on desktop computers.'),
        findsWidgets,
      );
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(applied, {
        'tool_choice': 'required',
        'parallel_tool_calls': true,
        'temperature': .2,
      });
    },
  );

  testWidgets(
    'JSON preview is readable without changing typed input or request value',
    (tester) async {
      Map<String, dynamic>? applied;
      await open(
        tester,
        model: const FreeModel(
          id: 'fixture/model:free',
          name: 'Fixture',
          supportedParameters: ['stop'],
        ),
        overrides: const {
          'stop': ['END'],
        },
        onApply: (value) => applied = value,
      );
      const source = '["END","NEXT"]';
      await tester.enterText(
        find.byKey(const Key('parameter-value-stop')),
        source,
      );
      await tester.tap(find.text('Readable preview'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<ReadableDataView>(find.byType(ReadableDataView)).source,
        source,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('parameter-value-stop')))
            .controller!
            .text,
        source,
      );
      final span = tester
          .widget<SelectableText>(find.byType(SelectableText))
          .textSpan!;
      expect(span.toPlainText(), '[\n  "END",\n  "NEXT"\n]');
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(applied, {
        'stop': ['END', 'NEXT'],
      });
    },
  );
  testWidgets('effort options follow advertised reasoning capabilities', (
    tester,
  ) async {
    final model = FreeModel.fromJson({
      ...fixture.toJson(),
      'supported_parameters': ['reasoning_effort'],
      'reasoning': {
        'mandatory': true,
        'supported_efforts': ['high', 'medium'],
      },
    });
    await open(tester, model: model, onApply: (_) {});
    expect(find.textContaining('Reasoning is mandatory'), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('parameter-enable-reasoning_effort')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('parameter-value-reasoning_effort')));
    await tester.pumpAndSettle();
    expect(find.text('high'), findsOneWidget);
    expect(find.text('medium'), findsOneWidget);
    expect(find.text('low'), findsNothing);
    expect(find.text('none'), findsNothing);
  });

  testWidgets(
    'reasoning with no effort selection keeps the capability visible',
    (tester) async {
      final model = FreeModel.fromJson({
        ...fixture.toJson(),
        'supported_parameters': ['reasoning_effort'],
        'reasoning': {'mandatory': true},
      });
      await open(tester, model: model, onApply: (_) {});
      expect(
        find.byKey(const Key('parameter-enable-reasoning_effort')),
        findsNothing,
      );
      expect(
        find.textContaining('does not advertise configurable reasoning effort'),
        findsOneWidget,
      );
    },
  );

  testWidgets('default omission and cancellation do not mutate caller state', (
    tester,
  ) async {
    final original = <String, dynamic>{'temperature': 0.7};
    Map<String, dynamic>? applied;
    await open(
      tester,
      overrides: original,
      onApply: (value) => applied = value,
    );
    await tester.enterText(
      find.byKey(const Key('parameter-value-temperature')),
      '0',
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(applied, null);
    expect(original, {'temperature': 0.7});
  });

  testWidgets('explicit zero is applied and resetting removes the key', (
    tester,
  ) async {
    Map<String, dynamic>? applied;
    await open(tester, onApply: (value) => applied = value);
    expect(find.textContaining('Provider defaults'), findsWidgets);
    await tester.tap(find.byKey(const Key('parameter-enable-temperature')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('parameter-value-temperature')),
      '0',
    );
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(applied, {'temperature': 0});
    await open(
      tester,
      overrides: applied!,
      onApply: (value) => applied = value,
    );
    await tester.tap(find.byKey(const Key('parameter-reset-temperature')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(applied, isEmpty);
  });

  testWidgets('invalid numeric and JSON input is explained and not applied', (
    tester,
  ) async {
    Map<String, dynamic>? applied;
    await open(
      tester,
      overrides: {'temperature': 0.5},
      onApply: (value) => applied = value,
    );
    await tester.enterText(
      find.byKey(const Key('parameter-value-temperature')),
      '99',
    );
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(applied, null);
    expect(find.textContaining('Enter a value from'), findsOneWidget);
    expect(find.byType(ParametersDialog), findsOneWidget);
    await tester.tap(find.text('Reset all'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('parameter-enable-stop')));
    await tester.tap(find.byKey(const Key('parameter-enable-stop')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('parameter-value-stop')),
      '{wrong',
    );
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(applied, null);
    expect(find.textContaining('Enter valid JSON'), findsOneWidget);
  });

  testWidgets('false is an explicit override and enum selection is typed', (
    tester,
  ) async {
    Map<String, dynamic>? applied;
    await open(
      tester,
      model: const FreeModel(
        id: 'fixture/model:free',
        name: 'Fixture',
        supportedParameters: ['logprobs', 'reasoning_effort'],
      ),
      onApply: (value) => applied = value,
    );
    await tester.tap(find.byKey(const Key('parameter-enable-logprobs')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('parameter-value-logprobs')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('false').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('parameter-enable-reasoning_effort')),
    );
    await tester.tap(
      find.byKey(const Key('parameter-enable-reasoning_effort')),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('parameter-value-reasoning_effort')),
    );
    await tester.tap(find.byKey(const Key('parameter-value-reasoning_effort')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('high').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(applied, {'logprobs': false, 'reasoning_effort': 'high'});
  });

  testWidgets(
    'unknown and managed capabilities remain visible without editors',
    (tester) async {
      await open(
        tester,
        model: const FreeModel(
          id: 'fixture/model:free',
          name: 'Fixture',
          supportedParameters: [
            'vendor_new',
            'tools',
            'web_search_options',
            'structured_outputs',
          ],
        ),
        onApply: (_) {},
      );
      expect(find.byKey(const Key('parameter-enable-tools')), findsNothing);
      expect(
        find.byKey(const Key('parameter-enable-web_search_options')),
        findsNothing,
      );
      await tester.ensureVisible(
        find.byKey(const Key('parameter-card-vendor_new')),
      );
      expect(find.textContaining('Not yet mapped'), findsWidgets);
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('parameter-card-vendor_new')),
          matching: find.text('Official information'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('official documentation'), findsWidgets);
    },
  );

  testWidgets(
    'narrow dialog supports 200 percent text, selectable help and reset',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await open(
        tester,
        scale: 2,
        overrides: {'temperature': 0.5},
        onApply: (_) {},
      );
      expect(find.byType(SelectionArea), findsWidgets);
      expect(tester.takeException(), null);
      await tester.tap(find.text('Reset all'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), null);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(ParametersDialog), findsNothing);
    },
  );
}
