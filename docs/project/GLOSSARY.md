# wfform glossary

| Term | Meaning in this project |
|---|---|
| Free-price candidate | Catalog entry whose applicable reported charges validate as zero; usability still depends on capabilities and provider availability. |
| Unresolved price | Exact -1 marker observed on routing entries. It is never zero and excludes applicable unresolved charges. Its semantics are inferred from live data and router behavior. |
| Quarantine | Retaining valid catalog entries while excluding and reporting an individual malformed DTO. Ordinary paid/unresolved exclusions are not schema failures. |
| Selected model | Explicit model ID associated with the open conversation. No automatic replacement occurs on failure or removal. |
| Provider | An upstream host serving a model through OpenRouter. Catalog presence and provider metadata are not proof of responsiveness. |
| Health observation | Timestamped recent probe/request outcome, scoped to model/configuration; it is not a guarantee for the next request. |
| Probe | Small inference used only for selected-model health when unknown/stale or explicitly rechecked. It consumes a request. |
| Allowance | Optional advisory counters from OpenRouter key metadata or rate-limit headers, not a promise of future acceptance. |
| Cooldown | Admission window honoring local backoff and server retry/reset information. It never schedules an automatic content resend. |
| Context boundary | Explicit first retained user turn sent in future requests. Earlier history remains stored. |
| Output reserve | Requested/capped response-token budget; context estimates include it. |
| Edit and resend | Append an updated copy of an earlier user message without erasing the original or current draft. |
| Continue answer | Explicit new turn requesting continuation after a length-stopped response. |
| Partial response | Received assistant content preserved after cancellation, truncation or another request failure. |
| Checkpoint | Durable normalized history save; also, in agent operations, a repository-local recovery note. The surrounding context distinguishes them. |
| Recovered copy | Separate conversation identity preserving a stale conflicting write; not an automatic merge. |
| Archived conversation | Preserved read-only history that can be restored or explicitly deleted. |
| PWA shell | Flutter runtime, app assets and minimal host files required to open the application offline. Remote chat still needs connectivity. |
| Release generation | Content-addressed, verified shell version retained in immutable paths and browser caches. |
| Origin | Scheme, host and port defining the browser storage boundary. A different localhost port has separate history. |
| xops | Repository automation using shell and Python stdlib; not application logic or a backend. |
| MCP / CodeGraph | Optional external agent-tool integration. Explicitly disabled in the initial full scaffold for this project. |
| Mocked check | Test using fixtures/fake transports/stores; cannot establish actual API or browser behavior. |
