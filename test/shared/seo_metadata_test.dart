import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wfform/app/app_identity.dart';

const publicPages = [
  'index.html',
  'about.html',
  'terms.html',
  'liability.html',
];

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
  const site = 'https://wfform.com/';
  final siteUri = Uri.parse(site);

  test(
    'public documents agree on canonical, sharing and crawlable identity',
    () {
      for (final path in publicPages) {
        final html = document(path);
        final url = '$site${path == 'index.html' ? '' : path}';
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
        expect(image.origin, siteUri.origin);
        expect(image.path, startsWith(siteUri.path));
        final imagePath = image.path.substring(siteUri.path.length);
        expect(File('web/$imagePath').existsSync(), isTrue);
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
    expect(website['url'], site);
    expect(website['@id'], '$site#website');
    expect(website['name'], 'wfform');
    expect(app['url'], site);
    expect(app['@id'], '$site#application');
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
      expect(robots, contains('Sitemap: ${site}sitemap.xml'));
      expect(robots, contains('User-agent: *'));
      expect(robots, contains('Disallow: /config/'));
      expect(robots, isNot(contains('Disallow: /\n')));
      expect(robots, isNot(contains('Disallow: /assets/')));
      expect(robots, isNot(contains('Disallow: /__releases/')));
      final locations = RegExp('<loc>([^<]+)</loc>')
          .allMatches(document('sitemap.xml'))
          .map((match) => match.group(1))
          .toList();
      expect(
        locations,
        unorderedEquals([
          site,
          '${site}about.html',
          '${site}terms.html',
          '${site}liability.html',
        ]),
      );
      expect(document('sitemap.xml'), isNot(contains('<lastmod>')));
    },
  );

  test('public explanation remains readable without launching Flutter', () {
    final about = document('about.html');
    expect(about, isNot(contains('flutter_bootstrap')));
    expect(about, contains('href="./"'));
    expect(about, contains('OpenRouter API key'));
    for (final page in publicPages.where((path) => path != 'index.html')) {
      expect(document(page), contains('>Open app</a>'));
      expect(document(page), isNot(contains('>Open the app</a>')));
    }
    expect(about, contains('limits'));
    final index = document('index.html');
    expect(index, contains('id="loading"'));
    expect(index, contains('href="about.html"'));
    expect(index, contains('<noscript>'));
  });

  test(
    'local navigation and icons work at the custom domain and localhost',
    () {
      for (final base in [siteUri, Uri.parse('http://localhost:8765/')]) {
        final about = base.resolve('about.html');
        expect(about.resolve('./'), base);
        expect(
          base.resolve('icons/Icon-192.png').path,
          '${base.path}icons/Icon-192.png',
        );
        for (final path in publicPages) {
          final html = document(path);
          final localResources = RegExp('(?:src|href)="([^":]+)"')
              .allMatches(html)
              .map((match) => match.group(1)!)
              .where((value) => !value.contains(r'$FLUTTER_BASE_HREF'));
          for (final relative in localResources) {
            expect(
              relative,
              isNot(startsWith('/')),
              reason: '$path: $relative',
            );
            expect(base.resolve(relative).path, startsWith(base.path));
          }
        }
      }
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('homepage: $site'));
    },
  );

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

  test('every HTML page has the requested tag once immediately after head', () {
    const tag = '''<!-- Google tag (gtag.js) -->
<script async src="https://www.googletagmanager.com/gtag/js?id=G-P3K2ZN7YTL"></script>
<script>
  window.dataLayer = window.dataLayer || [];
  function gtag(){dataLayer.push(arguments);}
  gtag('js', new Date());

  gtag('config', 'G-P3K2ZN7YTL');
</script>''';
    final htmlFiles = Directory(
      'web',
    ).listSync().whereType<File>().where((file) => file.path.endsWith('.html'));
    expect(htmlFiles, hasLength(publicPages.length));
    for (final file in htmlFiles) {
      final html = file.readAsStringSync();
      expect(html, contains('<head>\n$tag'), reason: file.path);
      expect(tag.allMatches(html), hasLength(1), reason: file.path);
      expect(
        RegExp(r'googletagmanager\.com/gtag/js').allMatches(html),
        hasLength(1),
      );
      expect(html, isNot(contains("gtag('event'")));
      expect(html, isNot(contains('localStorage')));
      expect(html, isNot(contains('sessionStorage')));
    }
  });

  test(
    'every public page links useful information and versioned source footer',
    () {
      for (final path in publicPages) {
        final html = document(path);
        for (final target in ['about.html', 'terms.html', 'liability.html']) {
          expect(html, contains('href="$target"'), reason: '$path → $target');
        }
        expect(html, contains('<footer'));
        expect(html, contains('<span>$appVersion</span>'));
        expect(
          html,
          contains('href="https://github.com/consciontologic/wfform"'),
        );
        expect(html, contains('src="github-mark.svg"'));
        expect(html, contains('href="site.css"'));
      }
      expect(File('web/github-mark.svg').existsSync(), isTrue);
      expect(File('web/site.css').existsSync(), isTrue);
      expect(
        File('pubspec.yaml').readAsStringSync(),
        contains('version: $appVersion+'),
      );
    },
  );

  test('public document ids and local fragment links have unique targets', () {
    final idsByPage = <String, List<String>>{
      for (final page in publicPages)
        page: RegExp(
          ' id="([^"]+)"',
        ).allMatches(document(page)).map((match) => match.group(1)!).toList(),
    };
    for (final entry in idsByPage.entries) {
      expect(entry.value.toSet().length, entry.value.length, reason: entry.key);
      for (final match in RegExp(
        'href="([^"]+)"',
      ).allMatches(document(entry.key))) {
        final uri = Uri.parse(match.group(1)!);
        if (uri.hasScheme || uri.fragment.isEmpty) continue;
        final target = uri.path.isEmpty ? entry.key : uri.path;
        expect(
          idsByPage[target],
          contains(uri.fragment),
          reason: '${entry.key} → $uri',
        );
      }
    }
  });

  test(
    'information pages remain readable documents with truthful data notices',
    () {
      for (final path in publicPages.skip(1)) {
        final html = document(path);
        expect(html, contains('href="#content"'));
        expect(html, contains('id="content"'));
        expect(html, contains('aria-label="Information pages"'));
        expect(html, isNot(contains('flutter_bootstrap')));
        expect(html, contains('href="./"'));
      }
      final terms = document('terms.html');
      expect(terms, contains('Google Analytics'));
      expect(terms, contains('cookies'));
      expect(terms, contains('https://openrouter.ai/terms'));
      expect(terms, contains('https://openrouter.ai/privacy'));
      expect(terms, contains('browser'));
      expect(terms, contains('directly'));
      final liability = document('liability.html');
      expect(liability, contains('applicable law'));
      expect(liability, contains('independent'));
      expect(liability, isNot(contains('all liability in all circumstances')));
    },
  );
}
