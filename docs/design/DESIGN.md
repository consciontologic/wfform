# Product and interaction design

The app helps users compare explicitly free models and maintain local conversations.
Keep controls understandable at compact, medium and expanded widths, including 200%
text scaling, keyboard navigation, touch and reduced motion.

- **Models** is a labeled searchable picker. Details distinguish pricing, capabilities
  and recent health; unavailable/incompatible choices explain why they cannot send.
- **Conversation** uses selectable Markdown/source views, separate returned reasoning,
  partial-output preservation and explicit Retry, Edit and resend, or Continue.
- **Composer** keeps text/files/focus across resizing and model changes. Acceptance
  clears the submitted draft; new composition is independent of an active answer.
- **Context** explicitly chooses earlier turns to exclude and the output reserve.
  Estimates never silently delete or summarize history.
- **History** separates Chats, Drafts and Archived. Archiving preserves read-only
  history; restoring permits continuation. Draft/archived deletion is explicit and
  permanent. Save failures remain visible and block navigation that would lose work.
- **Tools** is faded with an explanation on phones/tablets. Desktop users choose
  connections and tools, then approve each requested action. Ordinary chat needs none.
- **Settings** offers appearance, text size, saved browser key and PWA controls.
  Saved-key writes/clears report failure instead of claiming persistence.
- **Diagnostics** separates errors from activity and renders bounded structured data.
  Copy shortcuts are limited to full messages, code/file source and complete reports.

About, Terms and Liability open in the same tab only after a successful checkpoint;
Open app/Back restores that tab's conversation. GitHub opens separately.

Brand headings use Flutter paths. Roboto and Roboto Mono remain bundled for the
interface and code; keep their licenses beside the font files. Light/dark artwork and
transparent icons do not establish native store acceptance.

Detailed contracts: [history](../history.md), [chat](../chat.md),
[rendering](../file-rendering.md), [tools](../tools.md), [PWA](../pwa.md).

Current visual reference: [Open Cradle concept](open-cradle-concept.png). Generated
app/public/native assets are maintained by `tool/icons.dart`; this reference is not
a runtime asset or native acceptance evidence.
