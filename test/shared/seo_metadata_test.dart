import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String document(String path) => File('web/$path').readAsStringSync();

String meta(String html, String name) {
  final matches = RegExp(
    '<meta (?:name|property)="$name" content="([^"]+)">',
  ).allMatches(html).toList();
  expect(matches, hasLength(1), reason: '$name must be unambiguous');
  return matches.single.group(1)!;
}

String canonical(String html) {
  final matches = RegExp(
    '<link rel="canonical" href="([^"]+)">',
  ).allMatches(html).toList();
  expect(matches, hasLength(1));
  return matches.single.group(1)!;
}

void main() {
  const origin = 'https://wfform.com';

  test(
    'public documents agree on canonical, sharing and crawlable identity',
    () {
      for (final path in ['index.html', 'about.html']) {
        final html = document(path);
        final url = '$origin/${path == 'index.html' ? '' : path}';
        expect(canonical(html), url);
        expect(meta(html, 'og:url'), url);
        expect(meta(html, 'og:site_name'), 'wfform');
        expect(meta(html, 'description').length, inInclusiveRange(70, 220));
        expect(meta(html, 'og:description'), meta(html, 'description'));
        expect(meta(html, 'twitter:description'), meta(html, 'description'));
        expect(meta(html, 'robots'), isNot(contains('noindex')));
        final title = RegExp(
          '<title>([^<]+)</title>',
        ).firstMatch(html)!.group(1);
        expect(meta(html, 'og:title'), title);
        expect(meta(html, 'twitter:title'), title);
        expect(html, contains('<html lang="en">'));
        expect(RegExp('<h1[ >]').allMatches(html), hasLength(1));
        final image = Uri.parse(meta(html, 'og:image'));
        expect(image.origin, origin);
        expect(File('web${image.path}').existsSync(), isTrue);
        expect(meta(html, 'twitter:image'), image.toString());
        expect(meta(html, 'og:image:alt'), isNotEmpty);
      }
    },
  );

  test('structured data describes the actual app without invented ratings', () {
    final html = document('index.html');
    final json = RegExp(
      '<script type="application/ld\\+json">([\\s\\S]*?)</script>',
    ).firstMatch(html)!.group(1)!;
    final data = jsonDecode(json) as Map<String, dynamic>;
    expect(data['@context'], 'https://schema.org');
    final graph = (data['@graph'] as List).cast<Map<String, dynamic>>();
    final website = graph.singleWhere((node) => node['@type'] == 'WebSite');
    final app = graph.singleWhere((node) => node['@type'] == 'WebApplication');
    expect(website['url'], '$origin/');
    expect(website['name'], 'wfform');
    expect(app['url'], '$origin/');
    expect(app['applicationCategory'], 'ProductivityApplication');
    expect(app['browserRequirements'], contains('JavaScript'));
    expect(app['featureList'], isNotEmpty);
    expect(app, isNot(contains('aggregateRating')));
    expect(app, isNot(contains('review')));
    expect(app, isNot(contains('offers')));
    expect(app['description'], meta(html, 'description'));
  });

  test(
    'sitemap publishes only public pages and robots permits app resources',
    () {
      final robots = document('robots.txt');
      expect(robots, contains('Sitemap: $origin/sitemap.xml'));
      expect(robots, contains('User-agent: *'));
      expect(robots, isNot(contains('Disallow: /\n')));
      expect(robots, isNot(contains('Disallow: /assets/')));
      expect(robots, isNot(contains('Disallow: /__releases/')));
      final locations = RegExp('<loc>([^<]+)</loc>')
          .allMatches(document('sitemap.xml'))
          .map((match) => match.group(1))
          .toList();
      expect(locations, unorderedEquals(['$origin/', '$origin/about.html']));
      expect(document('sitemap.xml'), isNot(contains('<lastmod>')));
    },
  );

  test('public explanation remains readable without launching Flutter', () {
    final about = document('about.html');
    expect(about, isNot(contains('flutter_bootstrap')));
    expect(about, contains('href="./"'));
    expect(about, contains('OpenRouter API key'));
    expect(about, contains('limits'));
    final index = document('index.html');
    expect(index, contains('id="loading"'));
    expect(index, contains('href="about.html"'));
    expect(index, contains('<noscript>'));
  });

  test(
    'PWA categories enrich discovery without changing installation identity',
    () {
      final manifest = jsonDecode(document('manifest.json')) as Map;
      expect(
        manifest['categories'],
        containsAll(['productivity', 'utilities']),
      );
      expect(manifest['id'], './');
      expect(manifest['start_url'], './');
      expect(manifest['scope'], './');
      expect(manifest['name'], 'wfform');
      expect(
        manifest['description'],
        meta(document('index.html'), 'description'),
      );
    },
  );
}
