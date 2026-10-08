# Client-routed contact workspace

This slice tests whether conventional Vue navigation and independently fetched resources
improve page transitions and make local interactions easier to write. It reuses contact
scheduling and contact record components, readers, and durable scheduling commands.

Open `/missions/<mission-id>/ops/contact-workspace`, select a spacecraft, and open a
scheduled or realized contact. The corresponding record URL is
`/missions/<mission-id>/ops/contact-workspace/records/<contact-id>`. The existing
`/missions/<mission-id>/ops/contacts` entry remains available for comparison.

## Ownership

| Concern                                                                           | Owner                                            |
| --------------------------------------------------------------------------------- | ------------------------------------------------ |
| URL, route matching, links, Back/Forward                                          | Vue Router                                       |
| Loading, request cancellation, fetched resource cache, refresh                    | TanStack Vue Query                               |
| Search draft, reviewed cancellation, operation UI lifecycle                       | Existing scheduling component and domain service |
| Authorization, query validation, immutable review evidence, durable commands/jobs | Phoenix and Cadence                              |

There is one router in the workspace and no LiveSocket. Navigation commits immediately;
the new page displays its loading or error state independently of the read. No server
process stores a mutable current page. The HTTP controller only dispatches the existing
domain readers and operations. Neither Pinia nor a custom history implementation is needed.

The shared feature injects an optional navigation adapter. In this workspace, contact
schedule/record destinations use `RouterLink`; other destinations use normal anchors.
Native and federated hosts retain ordinary anchors. Modified clicks and new tabs retain
browser behavior. Route changes update the title, focus the page, and reset the content
scroll position; restoring prior scroll positions is outside this experiment.

## Resource and session boundaries

The two document routes are controller routes in the `/` scope, through `:browser` and
`:require_authenticated_scope`. They authenticate and authorize the mission before sending
a small shell bootstrap. They do not load contact page data before the shell can render.

The JSON scope `/api/cadence/contact-workspace/v1` uses `:browser` and
`:require_authenticated_user`, keeping session and CSRF protection. Every handler also
authorizes the explicit mission resource. It exposes schedule reads, contact record reads,
and the existing version 2 search/reserve/cancel/observe protocol. Path resource identity
cannot be replaced by a query parameter. These endpoints do not require a preceding catalog
or page request and have no application-host current-route dependency.

Cache keys contain actor, organization, mission, resource identity, and query. Every
response carries that session/resource identity and is decoded before rendering. Request
headers bind the tab to its bootstrapped actor and organization; the server checks them
against the authenticated session before effects. They are not authorization credentials.
A changed session clears the query cache and removes page actions until reload. The cache
is in memory, limited to this mounted workspace, and never persisted to browser storage.

Departed reads consume TanStack Query's abort signal; each page observer belongs to one
URL. Accepted mutations are durable domain operations, so leaving a page does not cancel
their jobs. A failed refresh cannot change the recorded outcome of an accepted mutation.
POST requests have no automatic retries. The existing operation identity/reconciliation
protocol handles uncertain outcomes.

## Freshness and scope

Active page data refreshes every five seconds while visible, on mount, and on focus or
reconnect when stale. Related cached resources are invalidated after scheduling commands.
Back can show cached data immediately while refreshing. Edits within a mounted page survive
background refresh; drafts are not retained after leaving that page. Offline and failed
refresh states are visible, with mutations disabled until recovery. Server authorization
and reviewed evidence remain authoritative even when cached data is visible.

This is polling, not push delivery. Live fleet posture, alarms, and notification subscriptions
are not implemented in this slice. Reservation review, organization switching, and other
workspace sections cross a normal document-navigation boundary. This slice does not yet
make those transitions faster. The shell's account context is bootstrapped once; session
changes are detected by subsequent resource requests.

## Evaluation

Component tests cover immediate navigation, cached Back, cancellation and late responses,
query-form routing, modified clicks, preserved local edits, retry, session changes, and
wrong resource identities. Controller tests cover authenticated deep links, independent
resource access, cross-organization denial, path identity, and CSRF.

The production browser scenario in `tools/phoenix/contact_schedule_browser.mjs` uses actual
Phoenix authentication and domain operations. It holds a record response while checking
that the URL and loading page have changed without replacing the shell, releases a failed
response and retries, holds a refresh while returning to the cached schedule, reloads a
record deep link, and cancels through the HTTP adapter. Native, federated, and client-routed
views recover the same durable operations. Its timing output is a controlled navigation
observation, not a production latency benchmark.

The local production-build run on 2026-09-30 UTC rendered the record URL and loading page
in 41 ms while its response was still held. It preserved the shell, rendered cached Back
before releasing the schedule refresh, preserved an edited search field, recovered from
the injected read failure, reloaded the record deep link, and recovered the HTTP cancellation
in the native host. Both provider effects occurred once. The rendered pages were also
visually checked. This measures the scripted click-to-loading transition on the local
machine, not end-to-end data availability or a before/after production comparison.

Before widening this approach, evaluate it with representative data and network latency,
then decide the push-update contract and the next whole workspace boundary. Avoid routing
the same URLs through both LiveSocket and Vue Router.
