import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wfform/config/app_config.dart';
import 'package:wfform/features/models/catalog.dart';
import 'package:wfform/features/models/model.dart';
import 'package:wfform/shared/diagnostics.dart';
import 'package:wfform/shared/platform.dart';
import 'package:wfform/shared/transport.dart';

Map<String, dynamic> fixture({
  String id = 'lab/model',
  Map<String, dynamic>? pricing,
  List<String> input = const ['text'],
  List<String> output = const ['text'],
}) => {
  'id': id,
  'name': 'Example model',
  'description': 'A deterministic fixture.',
  'context_length': 4096,
  'pricing': pricing ?? {'prompt': '0', 'completion': '0', 'request': '0'},
  'architecture': {'input_modalities': input, 'output_modalities': output},
  'supported_parameters': ['max_tokens', 'reasoning'],
  'top_provider': {'context_length': 4096, 'is_moderated': false},
};

ApiResponse response(Object body, {int status = 200}) =>
    ApiResponse(status, const {}, Stream.value(utf8.encode(jsonEncode(body))));

class FakeTransport implements ApiTransport {
  final List<Uri> uris = [];
  final List<CancelToken?> tokens = [];
  final List<Future<ApiResponse> Function()> replies = [];
  @override
  Future<ApiResponse> send(
    String method,
    Uri uri, {
    Map<String, String> headers = const {},
    Object? body,
    required Duration timeout,
    CancelToken? cancel,
  }) {
    expect(method, 'GET');
    expect(headers.containsKey('Authorization'), false);
    uris.add(uri);
    tokens.add(cancel);
    return replies.removeAt(0)();
  }

  void add(Object body, {int status = 200}) =>
      replies.add(() async => response(body, status: status));
}

void main() {
  test(
    'opt-in live public catalog adapter check',
    () async {
      const config = AppConfig(requestTimeout: Duration(seconds: 25));
      final diagnostics = Diagnostics(config);
      final catalog = CatalogController(
        config: config,
        transport: HttpApiTransport(),
        store: MemoryStore(),
        diagnostics: diagnostics,
      );
      addTearDown(catalog.dispose);
      await catalog.initialize();
      expect(
        catalog.error,
        null,
        reason: '${catalog.error?.message}: ${catalog.error?.details}',
      );
      expect(catalog.lastSuccess, isNotNull);
      // No brittle live counts or hardcoded selection. This also permits a truly
      // empty free catalog if the upstream service changes its offerings.
      expect(catalog.scannedCount, greaterThanOrEqualTo(catalog.models.length));
      // ignore: avoid_print
      print(
        'LIVE CATALOG: scanned=${catalog.scannedCount}; '
        'free-price candidates=${catalog.models.length}; '
        'chat-compatible=${catalog.models.where((m) => m.chatCompatible).length}; '
        'unresolved-pricing=${catalog.unresolvedPricingCount}; '
        'quarantined=${catalog.issueCount}; '
        'checked=${catalog.lastSuccess?.toIso8601String()}',
      );
    },
    skip: !const bool.fromEnvironment('RUN_LIVE_CATALOG'),
  );

  group('Pricing and forward-compatible model DTOs', () {
    test(
      'uploads require advertised modalities and preserve unknown prices',
      () {
        final textOnly = FreeModel.fromJson(fixture());
        expect(textOnly.allowedAttachmentMimeTypes, {'text/plain'});
        expect(textOnly.attachmentSummary, 'Text & source files');
        expect(
          textOnly.attachmentUnavailableReason('image'),
          contains('does not advertise'),
        );
        final multimodal = FreeModel.fromJson(
          fixture(
            id: 'lab/omni:free',
            input: ['text', 'image', 'audio', 'video', 'file'],
            pricing: {'prompt': '0', 'completion': '0'},
          ),
        );
        expect(multimodal.acceptsImages, true);
        expect(multimodal.acceptsAudio, true);
        expect(multimodal.acceptsVideo, true);
        expect(multimodal.acceptsPdf, true);
        expect(
          multimodal.pricing.keys,
          unorderedEquals(['prompt', 'completion']),
        );
        expect(
          multimodal.allowedAttachmentMimeTypes,
          containsAll([
            'image/png',
            'image/jpeg',
            'image/webp',
            'image/gif',
            'audio/wav',
            'audio/mpeg',
            'video/mp4',
            'application/pdf',
          ]),
        );
        expect(multimodal.allowedAttachmentMimeTypes, contains('text/plain'));
        expect(multimodal.attachmentNotice, contains('native file input only'));
      },
    );

    test(
      'audio and image price caps work without relying on a free suffix',
      () {
        final model = FreeModel.fromJson(
          fixture(input: ['text', 'image', 'audio']),
        );
        expect(model.acceptsImages, true);
        expect(model.acceptsAudio, true);
        expect(model.acceptsVideo, false);
        expect(model.acceptsPdf, false);
      },
    );

    test(
      'video requires validated free variant in absence of a video price cap',
      () {
        final model = FreeModel.fromJson(fixture(input: ['text', 'video']));
        expect(model.chatCompatible, true);
        expect(model.acceptsVideo, false);
        expect(
          model.attachmentUnavailableReason('video'),
          contains('video-price routing limit'),
        );
        final invalid = const FreeModel(
          id: 'lab/omni:free',
          name: 'Invalid',
          inputModalities: ['text', 'image', 'audio', 'video', 'file'],
          pricing: {'prompt': '0.0001', 'completion': '0'},
        );
        expect(invalid.allowedAttachmentMimeTypes, isEmpty);
      },
    );

    test(
      'reported media fees block only affected uploads and preserve text chat',
      () {
        for (final fee in [
          'image',
          'image_token',
          'audio',
          'input_audio_cache',
        ]) {
          final model = FreeModel.fromJson(
            fixture(
              id: 'lab/omni:free',
              input: ['text', 'image', 'audio', 'video', 'file'],
              pricing: {'prompt': '0', 'completion': '0', fee: '1e-999'},
            ),
          );
          expect(model.chatCompatible, true);
          expect(model.acceptsVideo, false, reason: fee);
          expect(model.acceptsImages, !fee.startsWith('image'), reason: fee);
          expect(model.acceptsPdf, !fee.startsWith('image'), reason: fee);
          expect(model.acceptsAudio, fee.startsWith('image'), reason: fee);
        }
      },
    );

    test('conditional media fees also disable uploads', () {
      final model = FreeModel.fromJson(
        fixture(
          id: 'lab/omni:free',
          input: ['text', 'image', 'audio', 'video'],
          pricing: {
            'prompt': '0',
            'completion': '0',
            'overrides': [
              {'min_prompt_tokens': 100, 'audio': '0.01'},
            ],
          },
        ),
      );
      expect(model.acceptsImages, true);
      expect(model.acceptsAudio, false);
      expect(model.acceptsVideo, false);
      expect(model.attachmentUnavailableReason('audio'), contains('override'));
    });

    test(
      'native PDFs require file capability; names and image inputs cannot imply it',
      () {
        final model = FreeModel.fromJson(
          fixture(
            id: 'lab/pdf:free',
            input: ['text', 'image', 'pdf', 'document'],
          ),
        );
        expect(model.acceptsImages, true);
        expect(model.acceptsPdf, false);
        expect(
          model.attachmentNotice,
          contains('native file input is not advertised'),
        );
        expect(
          model.attachmentUnavailableReason('document'),
          contains('not supported'),
        );
      },
    );

    test('inspect-only models cannot accept attachments', () {
      for (final item in [
        fixture(id: 'openrouter/free', input: ['text', 'image']),
        fixture(
          id: 'lab/multimodal:free',
          input: ['text', 'audio'],
          output: ['text', 'audio'],
        ),
      ]) {
        final model = FreeModel.fromJson(item);
        expect(model.allowedAttachmentMimeTypes, isEmpty);
      }
    });

    test(
      'numeric strings and numeric zeros are free without a :free suffix',
      () {
        final page = parseCatalog({
          'data': [
            fixture(
              pricing: {
                'prompt': '0.000e-20',
                'completion': 0,
                'request': '0.0',
              },
            ),
          ],
        });
        expect(page.models.single.id, 'lab/model');
        expect(page.models.single.chatCompatible, true);
      },
    );

    test('optional request price stays absent, never normalized to zero', () {
      final model = FreeModel.fromJson(
        fixture(pricing: {'prompt': '0', 'completion': '0'}),
      );
      expect(model.pricing.containsKey('request'), false);
      expect(model.pricingNotice, contains('not reported'));
    });

    for (final key in ['prompt', 'completion']) {
      test('missing required $key quarantines instead of becoming free', () {
        final item = fixture();
        (item['pricing'] as Map).remove(key);
        final page = parseCatalog({
          'data': [fixture(id: 'lab/valid'), item],
        });
        expect(page.models.single.id, 'lab/valid');
        expect(page.issues.single.field, '\$.data[1].pricing.$key');
      });
    }

    for (final bad in [
      null,
      '',
      'free',
      '-2',
      '-1.0',
      '-0',
      -0.1,
      'NaN',
      'Infinity',
      true,
      [],
      {},
    ]) {
      test('malformed price $bad is rejected', () {
        final page = parseCatalog({
          'data': [
            fixture(id: 'lab/valid'),
            fixture(pricing: {'prompt': bad, 'completion': '0'}),
          ],
        });
        expect(page.models, hasLength(1));
        expect(page.issues, hasLength(1));
      });
    }

    test('observed -1 sentinel is excluded without a schema quarantine', () {
      for (final sentinel in ['-1', ' -1 ', -1, -1.0]) {
        final page = parseCatalog({
          'data': [
            fixture(id: 'lab/valid'),
            fixture(
              id: 'new-author/router:free',
              pricing: {'prompt': sentinel, 'completion': '0'},
            ),
          ],
        });
        expect(page.models.single.id, 'lab/valid');
        expect(page.issues, isEmpty);
        expect(page.validCount, 2);
        expect(page.unresolvedPricingCount, 1);
        expect(page.exclusions.values.single, contains('unresolved'));
        expect(page.exclusions.values.single, contains('pricing.prompt = -1'));
        expect(isZeroPrice('$sentinel'), isFalse);
      }
    });

    test(
      'unresolved applicable request, unknown fees and overrides cannot be free',
      () {
        for (final key in ['completion', 'request', 'new_fee']) {
          final page = parseCatalog({
            'data': [
              fixture(pricing: {'prompt': '0', 'completion': '0', key: '-1'}),
            ],
          });
          expect(page.models, isEmpty);
          expect(page.issues, isEmpty);
          expect(page.unresolvedPricingCount, 1);
        }
        final page = parseCatalog({
          'data': [
            fixture(
              pricing: {
                'prompt': '0',
                'completion': '0',
                'overrides': [
                  {'prompt': '-1', 'min_prompt_tokens': 100},
                ],
              },
            ),
          ],
        });
        expect(page.models, isEmpty);
        expect(page.issues, isEmpty);
        expect(page.unresolvedPricingCount, 1);
        expect(page.exclusions.values.single, contains('overrides[0].prompt'));
      },
    );

    test(
      'unresolved media prices preserve text chat but disable that media',
      () {
        for (final conditional in [false, true]) {
          final page = parseCatalog({
            'data': [
              fixture(
                input: ['text', 'image'],
                pricing: {
                  'prompt': '0',
                  'completion': '0',
                  if (!conditional) 'image': '-1',
                  if (conditional)
                    'overrides': [
                      {'image': '-1', 'min_prompt_tokens': 100},
                    ],
                },
              ),
            ],
          });
          expect(page.issues, isEmpty);
          expect(page.unresolvedPricingCount, 0);
          expect(page.models.single.chatCompatible, true);
          expect(page.models.single.allowedAttachmentMimeTypes, {'text/plain'});
          expect(
            page.models.single.attachmentUnavailableReason('image'),
            contains('unresolved'),
          );
        }
        final imageOnly = parseCatalog({
          'data': [
            fixture(
              input: ['image'],
              output: ['image'],
              pricing: {'prompt': '0', 'completion': '0', 'image': '-1'},
            ),
          ],
        });
        expect(imageOnly.models, isEmpty);
        expect(imageOnly.unresolvedPricingCount, 1);
        expect(imageOnly.issues, isEmpty);
        expect(isUnresolvedPrice(' -1 '), true);
        expect(isUnresolvedPrice('-1.0'), false);
        expect(isUnresolvedPrice('-2'), false);
        expect(isUnresolvedPrice('0'), false);
      },
    );

    test('unresolved pricing does not hide another malformed field', () {
      final malformed = fixture(pricing: {'prompt': '-1', 'completion': '0'})
        ..['supported_parameters'] = false;
      final page = parseCatalog({
        'data': [fixture(id: 'lab/valid'), malformed],
      });
      expect(page.models.single.id, 'lab/valid');
      expect(page.unresolvedPricingCount, 0);
      expect(page.issues.single.field, r'$.data[1].supported_parameters');
    });

    test('malformed price diagnostics contain a bounded rejected scalar', () {
      final page = parseCatalog({
        'data': [
          fixture(id: 'lab/valid'),
          fixture(
            pricing: {'prompt': 'unexpected-${'x' * 500}', 'completion': '0'},
          ),
          fixture(
            id: 'lab/negative',
            pricing: {'prompt': '-2', 'completion': '0'},
          ),
          fixture(
            id: 'lab/object',
            pricing: {
              'prompt': {'secret': 'not copied'},
              'completion': '0',
            },
          ),
        ],
      });
      expect(page.issues, hasLength(3));
      expect(
        page.issues[0].failure.details,
        contains('Received pricing value: "unexpected-'),
      );
      expect(page.issues[0].failure.details!.length, lessThan(400));
      expect(page.issues[1].failure.details, contains('"-2"'));
      expect(
        page.issues[2].failure.details,
        contains('object (1 fields; content omitted)'),
      );
      expect(page.issues[2].failure.details, isNot(contains('not copied')));
    });

    test('tiny positive prices cannot underflow into free', () {
      final page = parseCatalog({
        'data': [
          fixture(pricing: {'prompt': '1e-999', 'completion': '0'}),
        ],
      });
      expect(page.models, isEmpty);
      expect(page.validCount, 1);
    });

    test(':free suffix cannot override a request or token charge', () {
      final page = parseCatalog({
        'data': [
          fixture(
            id: 'lab/model:free',
            pricing: {'prompt': '0', 'completion': '0', 'request': '0.001'},
          ),
        ],
      });
      expect(page.models, isEmpty);
      expect(page.exclusions['lab/model:free'], contains('request'));
    });

    test('reasoning, cache and unknown additional charges fail closed', () {
      for (final key in [
        'internal_reasoning',
        'input_cache_read',
        'input_cache_write',
        'future_fee',
      ]) {
        final page = parseCatalog({
          'data': [
            fixture(pricing: {'prompt': '0', 'completion': '0', key: '0.01'}),
          ],
        });
        expect(page.models, isEmpty, reason: key);
      }
    });

    test(
      'image-only paid output is not mislabeled free by zero token prices',
      () {
        final page = parseCatalog({
          'data': [
            fixture(
              output: ['image'],
              pricing: {
                'prompt': '0',
                'completion': '0',
                'image_output': '0.04',
              },
            ),
          ],
        });
        expect(page.models, isEmpty);
      },
    );

    test(
      'text-only requests do not incur optional image/web-search charges',
      () {
        final model = FreeModel.fromJson(
          fixture(
            pricing: {
              'prompt': '0',
              'completion': '0',
              'image': '1',
              'web_search': '1',
            },
          ),
        );
        expect(model.chatCompatible, true);
        expect(model.pricing['image'], '1');
      },
    );

    test('conditional paid pricing cannot become a later surprise charge', () {
      final page = parseCatalog({
        'data': [
          fixture(
            pricing: {
              'prompt': '0',
              'completion': '0',
              'overrides': [
                {'min_prompt_tokens': 2000, 'prompt': '0.0001'},
              ],
            },
          ),
        ],
      });
      expect(page.models, isEmpty);
      expect(page.exclusions.values.single, contains('Conditional'));
    });

    test(
      'harmless added fields and missing optional metadata are accepted',
      () {
        final item = fixture()
          ..addAll({
            'new_metadata': {'arbitrary': true},
          })
          ..remove('description')
          ..remove('name')
          ..remove('context_length')
          ..remove('top_provider')
          ..remove('supported_parameters');
        final model = FreeModel.fromJson(item);
        expect(model.name, model.id);
        expect(model.description, '');
        expect(model.contextLength, null);
        expect(model.supportsReasoning, false);
      },
    );

    test(
      'missing/renamed capabilities stay inspectable and cannot be selected',
      () {
        final item = fixture()
          ..['architecture'] = {
            'input_types': ['text'],
            'output_types': ['text'],
          };
        final model = FreeModel.fromJson(item);
        expect(model.chatCompatible, false);
        expect(model.incompatibilityReason, contains('not reported'));
      },
    );

    test('wrong-type optional fields are quarantined with exact paths', () {
      final item = fixture()..['context_length'] = 'many';
      final page = parseCatalog({
        'data': [fixture(id: 'lab/valid'), item],
      });
      expect(page.issues.single.failure.expected, contains('integer'));
      expect(page.issues.single.field, r'$.data[1].context_length');
    });

    test('non-chat free models and dynamic routers remain inspectable', () {
      final page = parseCatalog({
        'data': [
          fixture(id: 'lab/embedding', output: ['embeddings']),
          fixture(id: 'openrouter/free'),
        ],
      });
      expect(page.models, hasLength(2));
      expect(page.models.every((model) => !model.chatCompatible), true);
    });

    test(
      'text plus native audio or image output is inspect-only with zero token pricing',
      () {
        for (final output in [
          ['text', 'audio'],
          ['text', 'image'],
        ]) {
          final model = FreeModel.fromJson(
            fixture(
              input: ['text', 'image'],
              output: output,
              pricing: {'prompt': '0', 'completion': '0'},
            ),
          );
          expect(model.chatCompatible, false);
          expect(
            model.incompatibilityReason,
            contains('Native output charging cannot be guaranteed'),
          );
        }
        final textOnly = FreeModel.fromJson(fixture(input: ['text', 'image']));
        expect(textOnly.chatCompatible, true);
      },
    );

    test('genuine empty/paid-only response differs from parsing failure', () {
      expect(parseCatalog({'data': []}).models, isEmpty);
      expect(
        parseCatalog({
          'data': [
            fixture(pricing: {'prompt': '1', 'completion': '1'}),
          ],
        }).models,
        isEmpty,
      );
      expect(() => parseCatalog({'models': []}), throwsA(isA<AppFailure>()));
      expect(
        () => parseCatalog({
          'data': [{}],
        }),
        throwsA(isA<AppFailure>()),
      );
    });

    test('HTTP 200 error envelope is not an empty catalog', () {
      expect(
        () => parseCatalog({
          'error': {'code': 429, 'message': 'Rate limit'},
        }),
        throwsA(
          isA<AppFailure>().having(
            (f) => f.kind,
            'kind',
            FailureKind.rateLimit,
          ),
        ),
      );
    });

    test('model serialization and order-independent change detection', () {
      final model = FreeModel.fromJson(fixture());
      final restored = FreeModel.fromJson(model.toJson());
      expect(restored.signature, model.signature);
      final reordered = fixture()
        ..['supported_parameters'] = ['reasoning', 'max_tokens'];
      expect(FreeModel.fromJson(reordered).signature, model.signature);
    });
  });

  group('Catalog lifecycle', () {
    late FakeTransport transport;
    late MemoryStore store;
    late Diagnostics diagnostics;
    late DateTime now;
    const config = AppConfig(cacheTtl: Duration(hours: 1));
    CatalogController create() => CatalogController(
      config: config,
      transport: transport,
      store: store,
      diagnostics: diagnostics,
      now: () => now,
    );
    setUp(() {
      transport = FakeTransport();
      store = MemoryStore();
      diagnostics = Diagnostics(config);
      now = DateTime.utc(2026, 10, 5, 10);
    });

    test(
      'loads API catalog using documented all-modalities parameter',
      () async {
        transport.add({
          'data': [fixture()],
        });
        final catalog = create();
        addTearDown(catalog.dispose);
        await catalog.initialize();
        expect(catalog.models, hasLength(1));
        expect(catalog.lastSuccess, now);
        expect(catalog.selectedId, null);
        expect(catalog.fromCache, false);
        expect(transport.uris.single.queryParameters, {
          'output_modalities': 'all',
        });
        expect(store.read(CatalogController.cacheKey), isNotNull);
      },
    );

    test(
      'refreshes are deduplicated and each new launch refreshes cached data',
      () async {
        final completer = Completer<ApiResponse>();
        transport.replies.add(() => completer.future);
        final first = create();
        addTearDown(first.dispose);
        final a = first.initialize();
        final b = first.refresh();
        expect(transport.uris, hasLength(1));
        completer.complete(
          response({
            'data': [fixture()],
          }),
        );
        await Future.wait([a, b]);
        final next = Completer<ApiResponse>();
        transport.replies.add(() => next.future);
        final second = create();
        addTearDown(second.dispose);
        final launch = second.initialize();
        expect(second.models, hasLength(1));
        expect(second.fromCache, true);
        expect(second.refreshing, true);
        expect(second.stale, false);
        next.complete(
          response({
            'data': [fixture()],
          }),
        );
        await launch;
        expect(transport.uris, hasLength(2));
      },
    );

    test(
      'cache-only initialization makes no remote call and allows manual refresh',
      () async {
        store.write(
          CatalogController.cacheKey,
          jsonEncode({
            'version': 1,
            'apiBaseUrl': config.apiBaseUrl,
            'savedAt': now
                .subtract(const Duration(minutes: 30))
                .toIso8601String(),
            'models': [fixture()],
          }),
        );
        final catalog = create();
        addTearDown(catalog.dispose);
        await catalog.initialize(refresh: false);
        expect(catalog.models.single.id, 'lab/model');
        expect(catalog.fromCache, true);
        expect(catalog.refreshing, false);
        expect(transport.uris, isEmpty);
        transport.add({
          'data': [fixture(id: 'lab/fresh')],
        });
        await catalog.refresh();
        expect(transport.uris, hasLength(1));
        expect(catalog.models.single.id, 'lab/fresh');
        expect(catalog.fromCache, false);
        expect(diagnostics.export(), contains('1 pages'));
      },
    );

    test(
      'cache TTL and failed refresh retain stale last-success data',
      () async {
        transport.add({
          'data': [fixture()],
        });
        final first = create();
        await first.initialize();
        first.dispose();
        now = now.add(const Duration(hours: 2));
        transport.add({'renamed_data': []});
        final catalog = create();
        addTearDown(catalog.dispose);
        await catalog.initialize();
        expect(catalog.models, hasLength(1));
        expect(catalog.stale, true);
        expect(catalog.fromCache, true);
        expect(catalog.error?.kind, FailureKind.schema);
        expect(catalog.lastSuccess, now.subtract(const Duration(hours: 2)));
      },
    );

    test(
      'follows safe pagination with all modalities and rejects incomplete result',
      () async {
        transport.add({
          'data': [fixture(id: 'lab/one')],
          'total_count': 2,
          'links': {'next': '/api/v1/models?offset=1&limit=1'},
        });
        transport.add({
          'data': [fixture(id: 'lab/two')],
          'total_count': 2,
          'links': {'next': null},
        });
        final catalog = create();
        addTearDown(catalog.dispose);
        await catalog.initialize();
        expect(catalog.models, hasLength(2));
        expect(transport.uris.last.queryParameters['output_modalities'], 'all');
        transport.add({
          'data': [fixture()],
          'total_count': 8,
        });
        await catalog.refresh();
        expect(catalog.models, hasLength(2));
        expect(catalog.error?.message, contains('incomplete'));
      },
    );

    test(
      'pagination cannot redirect catalog reads to an unrelated server',
      () async {
        transport.add({
          'data': [fixture()],
          'links': {'next': 'https://example.invalid/models'},
        });
        final catalog = create();
        addTearDown(catalog.dispose);
        await catalog.initialize();
        expect(transport.uris, hasLength(1));
        expect(catalog.error?.field, r'$.links.next');
      },
    );

    test(
      'a malformed page does not discard valid entries from other pages',
      () async {
        transport.add({
          'data': [fixture()],
          'total_count': 2,
          'links': {'next': '/api/v1/models?offset=1&limit=1'},
        });
        transport.add({
          'data': [
            {'id': 'lab/bad'},
          ],
          'total_count': 2,
          'links': {'next': null},
        });
        final catalog = create();
        addTearDown(catalog.dispose);
        await catalog.initialize();
        expect(catalog.models.single.id, 'lab/model');
        expect(catalog.issueCount, 1);
        expect(catalog.issues.single.modelId, 'lab/bad');
        expect(catalog.error, null);
      },
    );

    test(
      'selected model removal/paid change clears selection and explains why',
      () async {
        transport.add({
          'data': [fixture()],
        });
        final catalog = create();
        addTearDown(catalog.dispose);
        await catalog.initialize();
        catalog.select('lab/model');
        transport.add({
          'data': [
            fixture(
              pricing: {'prompt': '0', 'completion': '0', 'request': '0.1'},
            ),
          ],
        });
        await catalog.refresh();
        expect(catalog.selectedId, null);
        expect(catalog.selectionNotice, contains('request'));
        expect(catalog.models, isEmpty);
      },
    );

    test(
      'changed supported parameters require explicit model reselection',
      () async {
        transport.add({
          'data': [fixture()],
        });
        final catalog = create();
        addTearDown(catalog.dispose);
        await catalog.initialize();
        catalog.select('lab/model');
        transport.add({
          'data': [
            fixture()..['supported_parameters'] = ['max_tokens'],
          ],
        });
        await catalog.refresh();
        expect(catalog.selectedId, null);
        expect(catalog.selectionNotice, contains('capabilities changed'));
        expect(catalog.changedCount, 1);
      },
    );

    test('quarantine retains valid entries and reports exact counts', () async {
      transport.add({
        'data': [
          fixture(),
          {'id': 'bad/model'},
        ],
      });
      final catalog = create();
      addTearDown(catalog.dispose);
      await catalog.initialize();
      expect(catalog.models, hasLength(1));
      expect(catalog.issueCount, 1);
      expect(catalog.issues.single.modelId, 'bad/model');
      expect(catalog.error, null);
    });

    test(
      'unresolved prices produce one refresh summary and invalidate selection',
      () async {
        transport.add({
          'data': [fixture()],
        });
        final catalog = create();
        addTearDown(catalog.dispose);
        await catalog.initialize();
        catalog.select('lab/model');
        transport.add({
          'data': [
            fixture(pricing: {'prompt': '-1', 'completion': '-1'}),
            fixture(
              id: 'lab/router-two',
              pricing: {'prompt': '-1', 'completion': '-1'},
            ),
          ],
        });
        await catalog.refresh();
        expect(catalog.error, isNull);
        expect(catalog.models, isEmpty);
        expect(catalog.issueCount, 0);
        expect(catalog.unresolvedPricingCount, 2);
        expect(catalog.selectedId, isNull);
        expect(catalog.selectionNotice, contains('unresolved'));
        expect(
          diagnostics.events.where(
            (event) => event.data['operation'] == 'catalog.quarantine',
          ),
          isEmpty,
        );
        final summaries = diagnostics.events.where(
          (event) => event.data['operation'] == 'catalog.refresh',
        );
        expect(summaries, hasLength(2));
        expect(
          summaries.first.data['summary'],
          contains('2 excluded with unresolved pricing (-1)'),
        );
        expect(summaries.first.data['kind'], 'success');

        // A valid catalog containing only unresolved prices is a successful
        // empty free catalog; a genuinely malformed later refresh retains it.
        transport.add({
          'data': [
            fixture(pricing: {'prompt': 'bad', 'completion': '0'}),
          ],
        });
        final refreshedAt = catalog.lastSuccess;
        await catalog.refresh();
        expect(catalog.error?.kind, FailureKind.schema);
        expect(
          catalog.error?.details,
          contains('Received pricing value: "bad"'),
        );
        expect(catalog.lastSuccess, refreshedAt);
        expect(catalog.unresolvedPricingCount, 2);
        expect(catalog.models, isEmpty);
        final cached = create();
        addTearDown(cached.dispose);
        await cached.initialize(refresh: false);
        expect(cached.fromCache, true);
        expect(cached.models, isEmpty);
      },
    );

    test(
      'dispose cancels an in-flight refresh without notifying later',
      () async {
        final pending = Completer<ApiResponse>();
        transport.replies.add(() => pending.future);
        final catalog = create();
        final future = catalog.initialize();
        catalog.dispose();
        expect(transport.tokens.single!.isCancelled, true);
        pending.complete(
          response({
            'data': [fixture()],
          }),
        );
        await future;
      },
    );
  });
}
