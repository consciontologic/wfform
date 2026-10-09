# Search and project metadata

Updated 2026-10-07. The canonical public site is
**https://wfform.com/**, using GitHub Pages hosting with the user's custom domain.
The domain replaces the earlier `consciontologic.github.io/wfform.com/` URL.
The source repository and artifact destination remain unchanged.

## Implemented metadata

- `web/index.html` has an English language declaration, descriptive title,
  description, one absolute canonical URL, Open Graph and Twitter summary-card
  metadata, and JSON-LD describing a `WebSite` and `WebApplication`.
- The app is classified as a productivity application for AI chat and model
  discovery. Structured data describes existing features only; it contains no
  invented reviews, ratings, prices, usage guarantees, or organization claims.
- `web/about.html`, `web/terms.html` and `web/liability.html` are public information
  documents with individual titles, descriptions, canonical URLs and sharing
  metadata. Their content works without JavaScript. Shared local CSS supplies
  responsive light/dark presentation, and all pages link back to the app and repository.
- `web/sitemap.xml` lists the homepage, About, Terms and Liability pages at the custom-domain root.
  The shipped `web/robots.txt` is served at `https://wfform.com/robots.txt`, where
  crawlers consult it. It permits public app resources, excludes `/config/` from
  crawling and advertises the sitemap. This rule is not access control; public
  builds still exclude local configuration. The public HTML permits indexing
  through its robots meta tags.
- All four public pages declare transparent 16px, 32px and 48px PNG favicons using the approved soft W-wrapper mark, with dark variants selected by `prefers-color-scheme`. Information-page logos use the same appearance selection through `picture`. PWA, Apple touch, sharing and public-page brand images use the matching generated launcher artwork. The release allowlist hashes and publishes every favicon size so browser tabs and offline pages receive the replacement too.
- `web/manifest.json` adds productivity/utility categories and a descriptive
  summary while preserving the existing installed-app `id`, `start_url` and
  `scope`. The same logo serves as the app icon and social preview image.
- `pubspec.yaml` identifies the homepage, source repository, issue tracker,
  description and relevant project topics. It remains unpublished to pub.dev.

These files are included in the release by `tool/build.dart` and remain ordinary
static assets. They add no application framework, API proxy or runtime package. The user-requested
Google tag is the only added third-party analytics integration. All chat, storage and interaction logic remains Flutter/Dart.

## Flutter boundary

Flutter renders an application rather than a conventional document site. Normal
homepage startup uses a quiet, theme-matched shell without a product introduction
or About content flashing before the app. The bootstrap removes that startup
surface after Flutter takes over. A small inline guard runs before the bootstrap
script so a failed bootstrap download can reveal recovery guidance even when
Flutter cannot load. Bootstrap/engine startup failures use the same recovery
surface, and a no-JavaScript fallback links to the static About page.

The homepage retains its descriptive title, search/sharing metadata and JSON-LD;
the Flutter app preserves the browser title. Search engines may not index text
drawn by Flutter, so `about.html` provides persistent crawlable product and
getting-started information. It is an explanatory document, not a second
application or a special response served only to bots.

The sitemap never includes conversations, model-search results, private browser
state or versioned release paths. No current model count or fixed list of free
models is published: availability and pricing change. The content explains that
chat requires an OpenRouter API key and network access, and that provider/account
limits still apply. The app's structured data aids interpretation; it does not
claim eligibility for a particular Google rich result.

## Publishing and Google Search Console

1. Deploy the public build with Flutter base href `/` and enable GitHub Pages
   for the destination repository, with custom domain `wfform.com`. The publisher
   maintains the matching `CNAME` file. Follow the
   [publishing guide](guides/CI_CD.md) for the artifact workflow and Pages setup.
2. Fetch the homepage, `about.html`, `sitemap.xml` and `icons/Icon-512.png`
   beneath `https://wfform.com/`. Check HTTP 200,
   content types and canonical URLs. Unknown paths should return 404, not a
   duplicate homepage. Ensure the host does not add a `noindex` header. Check
   `https://wfform.com/robots.txt` separately.
3. Add a **Domain property** for `wfform.com` in Google Search Console and use
   its supplied DNS verification record, or add a **URL-prefix property** for
   `https://wfform.com/`. For URL-prefix HTML-tag verification, add the exact supplied
   `google-site-verification` meta tag to `web/index.html`, redeploy, and verify.
   No verification token is fabricated or committed here. GitHub domain setup
   does not verify Google Search Console ownership automatically.
4. Submit `https://wfform.com/sitemap.xml`. Use URL
   Inspection for both public pages, including the rendered HTML, then request
   indexing if appropriate.
   Use the Rich Results Test to inspect detected structured data; an absence of
   a supported rich-result type does not make generic Schema.org metadata invalid.
5. Review real Search Console indexing and performance reports after Google
   visits. Local browser tests cannot establish indexing, ranking, Core Web
   Vitals from real visitors, or social-platform preview refreshes.

Keep the canonical URL `https://wfform.com/` consistent across HTML,
JSON-LD, sharing images, sitemap, pubspec and deployment configuration. If the
public URL changes, update these together and the metadata tests. Local links
and icon paths stay relative, so root localhost development still works.
For publicly reachable temporary previews, configure the preview host to send
`X-Robots-Tag: noindex`; localhost verification does not need this.

Do not add meta-keyword lists, hidden text, fake ratings, or promises of unlimited
free chat. No search position, indexing time or exact search snippet is
guaranteed. Google may choose a different title or description.

## Checks

```sh
flutter test test/shared/seo_metadata_test.dart test/shared/pwa_identity_test.dart
make verify
make build.public
```

The focused tests validate canonical/sharing agreement, descriptive metadata,
JSON-LD structure, local preview assets, public sitemap scope, readable static
content and preserved PWA identity. Release/browser verification separately
checks serving, quiet startup and the failure/no-JavaScript fallbacks; public
indexing requires a reachable Pages site.

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

## Google Analytics and visible version

Each of the four HTML pages includes the supplied Google tag for
`G-P3K2ZN7YTL` once, immediately after `<head>`. The standard asynchronous
loader initializes page measurement. No custom analytics events or user IDs
are added for messages, API keys, attachments or conversation history.
Collection can be blocked by browser privacy settings or extensions; no app
feature depends on analytics success. About and Terms disclose analytics and
link to Google's privacy information. Analytics cookies/property options remain
managed by Google and the site operator; these informational pages do not
certify jurisdiction-specific legal compliance.

The PWA only caches approved same-origin shell files. Google scripts, requests
and responses are not included in that shell cache. Nginx permits the Google
loader, a hash of the exact analytics snippet and the specified analytics
connection/image origins. The homepage's bootstrap-download guard has a separate
exact script hash. When either inline snippet changes, including whitespace,
update its hash in `deploy/nginx/headers.conf`; leave the other snippet's hash
unchanged. Regression tests calculate both hashes from the HTML. Script execution
does not allow `unsafe-inline`, and inline event-handler attributes remain
disabled. See
[Google's current CSP guidance](https://developers.google.com/tag-platform/security/guides/csp)
(verified 2026-10-07) and the [Docker guide](guides/DOCKER.md).

The Flutter footer and public documents display version **0.2.1**. When bumping
a release, update `pubspec.yaml`, `lib/app/app_identity.dart`, the static page
footers and any structured version metadata together; deterministic tests
check consistency. Footer information links open in the same tab after a
successful draft checkpoint, retaining that tab's restoration identity. Active
requests, file picking and failed saves prevent leaving the app. The GitHub
source link opens separately and sits beside the version on the left,
without logo artwork on any page. Compact layouts use an Info menu; the footer yields space while
a software keyboard is open.
