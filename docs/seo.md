# Search and project metadata

Updated 2026-10-07. The intended public origin is **https://wfform.com/**. The
artifact repository name alone does not establish a working domain: configure
the host and DNS before submitting the site to a search engine.

## Implemented metadata

- `web/index.html` has an English language declaration, descriptive title,
  description, one absolute canonical URL, Open Graph and Twitter summary-card
  metadata, and JSON-LD describing a `WebSite` and `WebApplication`.
- The app is classified as a productivity application for AI chat and model
  discovery. Structured data describes existing features only; it contains no
  invented reviews, ratings, prices, usage guarantees, or organization claims.
- `web/about.html` is a small, visible product and getting-started document with
  its own title, description, canonical URL and sharing metadata. It works
  without JavaScript and links back to the Flutter app and source repository.
- `web/robots.txt` permits public pages and the resources needed to render the
  app. It links to `web/sitemap.xml`, which lists the homepage and About page.
  `/config/` is excluded from crawling; robots directives are not access control.
- `web/manifest.json` adds productivity/utility categories and a descriptive
  summary while preserving the existing installed-app `id`, `start_url` and
  `scope`. The same logo serves as the app icon and social preview image.
- `pubspec.yaml` identifies the homepage, source repository, issue tracker,
  description and relevant project topics. It remains unpublished to pub.dev.

These files are included in the release by `tool/build.dart` and remain ordinary
static assets. They add no application framework, API proxy, tracking script or
runtime package. All chat, storage and interaction logic remains Flutter/Dart.

## Flutter boundary

Flutter renders an application rather than a conventional document site. The
homepage now supplies meaningful, visible HTML while Flutter starts; the
existing bootstrap removes that loading surface after the app takes over. The
Flutter app preserves the descriptive browser title. Search engines may not
index text drawn by Flutter, so `about.html` provides persistent crawlable
product information. It is an explanatory document, not a second application or
a special response served only to bots.

The sitemap never includes conversations, model-search results, private browser
state or versioned release paths. No current model count or fixed list of free
models is published: availability and pricing change. The content explains that
chat requires an OpenRouter API key and network access, and that provider/account
limits still apply. The app's structured data aids interpretation; it does not
claim eligibility for a particular Google rich result.

## Publishing and Google Search Console

1. Deploy the public build and connect `wfform.com` to the actual static host.
   Serve the canonical HTTPS origin successfully and redirect alternate public
   hostnames to it. Follow the [publishing guide](guides/CI_CD.md) for the artifact
   workflow and host setup.
2. Fetch `/`, `/about.html`, `/robots.txt`, `/sitemap.xml` and
   `/icons/Icon-512.png` from the public origin. Check HTTP 200, content types and
   the final canonical host. Unknown paths should return 404, not a duplicate
   homepage. Ensure the host does not add a `noindex` header.
3. Add a Domain property for `wfform.com` in Google Search Console and complete
   its DNS verification. No verification token is fabricated or committed here.
4. Submit `https://wfform.com/sitemap.xml`. Use URL Inspection for both public
   pages, including the rendered HTML, then request indexing if appropriate.
   Use the Rich Results Test to inspect detected structured data; an absence of
   a supported rich-result type does not make generic Schema.org metadata invalid.
5. Review real Search Console indexing and performance reports after Google
   visits. Local browser tests cannot establish indexing, ranking, Core Web
   Vitals from real visitors, or social-platform preview refreshes.

Keep the canonical host consistent across HTML, JSON-LD, sharing images,
robots, sitemap, pubspec and deployment configuration. If the real public origin
changes, update these together and the metadata tests. A project/subpath preview
must not accidentally become a competing canonical site. For publicly reachable
temporary previews, configure the preview host to send `X-Robots-Tag: noindex`;
localhost verification does not need this.

Do not add meta-keyword lists, hidden text, fake ratings, or promises of unlimited
free chat. No search position, indexing time or exact search snippet is
guaranteed. Google may choose a different title or description.

## Checks

```sh
flutter test test/shared/seo_metadata_test.dart test/shared/pwa_identity_test.dart
make verify
make build
```

The focused tests validate canonical/sharing agreement, descriptive metadata,
JSON-LD structure, local preview assets, public sitemap scope, readable static
content and preserved PWA identity. Release/browser verification separately
checks serving and Flutter startup; public indexing requires a published domain.

## Sources checked on 2026-10-07

- [Flutter web FAQ: search engine optimization](https://docs.flutter.dev/platform-integration/web/faq#search-engine-optimization-seo)
- [Google: JavaScript SEO basics](https://developers.google.com/search/docs/crawling-indexing/javascript/javascript-seo-basics)
- [Google: descriptive title links](https://developers.google.com/search/docs/appearance/title-link)
- [Google: meta descriptions and snippets](https://developers.google.com/search/docs/appearance/snippet)
- [Google: build and submit a sitemap](https://developers.google.com/search/docs/crawling-indexing/sitemaps/build-sitemap)
- [Schema.org WebApplication](https://schema.org/WebApplication)
