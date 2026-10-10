# Search and public information

Canonical site: **https://wfform.com/**. Keep HTML, JSON-LD, sharing images, sitemap,
pubspec and deployment base `/` consistent. [CI/CD](guides/CI_CD.md) owns Pages/DNS.

- `web/index.html` provides title/description, canonical URL, Open Graph/Twitter and
  WebSite/WebApplication structured data; never invent ratings or unlimited free use.
- `about.html`, `terms.html`, `liability.html` are readable static documents with their
  own metadata and shared responsive light/dark CSS. They are included in sitemap.
- Homepage startup stays quiet until Flutter renders; bootstrap errors/no-JavaScript
  expose recovery/About links. Static information does not replace Flutter app logic.
- `robots.txt` lives at the host root; excluding config from crawling is not access
  control. Public packages must exclude it independently. Private chat/state is never
  in the sitemap.
- Open Cradle icons/favicons include light/dark variants. Keep asset allowlists and
  preserved manifest `id`, `start_url`, `scope` aligned.

## Analytics and version

The four HTML pages load owner-supplied tag `G-P3K2ZN7YTL` once. No custom message,
key, file, user-ID or history events. Privacy blocking must not break the app. About/
Terms disclose analytics and link Google's privacy information; this is not a claim
of jurisdiction-specific compliance. Google resources never enter the PWA shell cache.

Nginx allows the bounded loader/endpoints plus exact snippet hashes. Update the
corresponding CSP hash when analytics/bootstrap inline text changes, including whitespace;
never enable unrestricted inline scripts. Tests calculate the hashes.

`make version.sync` aligns pubspec, app identity and public version text. Information
links wait for a successful draft checkpoint; Open app/Back preserves same-tab context.

## Publication checks

Check public homepage/About/Terms/Liability, sitemap, robots and icons for correct
status/MIME/canonical; unknown paths should be 404. Configure Search Console Domain or
URL-prefix ownership using its actual supplied verification token, submit
`https://wfform.com/sitemap.xml`, then inspect real indexing/performance reports.
GitHub domain configuration does not verify Google ownership. Local tests cannot prove
ranking, visitor Core Web Vitals, indexing time or social preview refreshes.

Run `flutter test test/shared/seo_metadata_test.dart test/shared/pwa_identity_test.dart`
and verify release-browser quiet startup/failure fallbacks. Source guidance:
[Flutter SEO limits](https://docs.flutter.dev/platform-integration/web/faq#search-engine-optimization-seo),
[Google sitemaps](https://developers.google.com/search/docs/crawling-indexing/sitemaps/build-sitemap),
[Google tag CSP](https://developers.google.com/tag-platform/security/guides/csp).
