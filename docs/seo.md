# Search and project metadata

Updated 2026-10-07. The canonical public site is
**https://consciontologic.github.io/wfform.com/**, using free GitHub Pages hosting.
The user does not own the `wfform.com` domain; it is only the destination
repository name. No domain purchase, DNS configuration or custom domain is needed.

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
- `web/sitemap.xml` lists the homepage and About page under `/wfform.com/`.
  The shipped `web/robots.txt` copy documents the sitemap URL and a scoped
  `/wfform.com/config/` rule, but **Google does not use a robots.txt file in a
  subdirectory**. Crawlers consult `https://consciontologic.github.io/robots.txt`,
  which is outside this project repository's deployed path. Do not claim the
  project copy controls crawling. The public HTML permits indexing through its
  robots meta tags, and the sitemap can be submitted directly to Search Console.
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

1. Deploy the public build with Flutter base href `/wfform.com/` and enable
   GitHub Pages for the destination repository. Leave its custom-domain setting
   empty and do not publish a `CNAME` file. Follow the
   [publishing guide](guides/CI_CD.md) for the artifact workflow and Pages setup.
2. Fetch the homepage, `about.html`, `sitemap.xml` and `icons/Icon-512.png`
   beneath `https://consciontologic.github.io/wfform.com/`. Check HTTP 200,
   content types and canonical URLs. Unknown paths should return 404, not a
   duplicate homepage. Ensure the host does not add a `noindex` header. Check
   the host-root robots policy separately; the project copy is informational.
3. Add a **URL-prefix property** for
   `https://consciontologic.github.io/wfform.com/` in Google Search Console.
   Use its HTML-tag verification method: add the exact supplied
   `google-site-verification` meta tag to `web/index.html`, redeploy, and verify.
   No verification token is fabricated or committed here. DNS verification of
   the unowned `github.io` or `wfform.com` domain is not part of this setup.
4. Submit `https://consciontologic.github.io/wfform.com/sitemap.xml`. Use URL
   Inspection for both public pages, including the rendered HTML, then request
   indexing if appropriate.
   Use the Rich Results Test to inspect detected structured data; an absence of
   a supported rich-result type does not make generic Schema.org metadata invalid.
5. Review real Search Console indexing and performance reports after Google
   visits. Local browser tests cannot establish indexing, ranking, Core Web
   Vitals from real visitors, or social-platform preview refreshes.

Keep the canonical URL, including `/wfform.com/`, consistent across HTML,
JSON-LD, sharing images, sitemap, pubspec and deployment configuration. If the
public URL changes, update these together and the metadata tests. Local links
and startup images stay relative, so root localhost development still works.
For publicly reachable temporary previews, configure the preview host to send
`X-Robots-Tag: noindex`; localhost verification does not need this.

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
checks serving and Flutter startup; public indexing requires a reachable Pages site.

## Sources checked on 2026-10-07

- [Flutter web FAQ: search engine optimization](https://docs.flutter.dev/platform-integration/web/faq#search-engine-optimization-seo)
- [Google: JavaScript SEO basics](https://developers.google.com/search/docs/crawling-indexing/javascript/javascript-seo-basics)
- [Google: descriptive title links](https://developers.google.com/search/docs/appearance/title-link)
- [Google: meta descriptions and snippets](https://developers.google.com/search/docs/appearance/snippet)
- [Google: build and submit a sitemap](https://developers.google.com/search/docs/crawling-indexing/sitemaps/build-sitemap)
- [Google: robots.txt host-root requirement](https://developers.google.com/crawling/docs/robots-txt/create-robots-txt)
- [Search Console: add a URL-prefix property](https://support.google.com/webmasters/answer/34592?hl=en)
- [Search Console: HTML-tag ownership verification](https://support.google.com/webmasters/answer/9008080?hl=en)
- [Schema.org WebApplication](https://schema.org/WebApplication)
