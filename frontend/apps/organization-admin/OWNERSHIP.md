# Organization administration ownership

This remote renders organization and platform administration screens. Shared controls and
styles come from `@cadence/ui` and `@cadence/design-tokens`.

Provider-account directory, registration and detail are Communications-owned features.
The four historical `ProviderAccount*.vue` entries delegate to
`@cadence/communications/provider-accounts`; their implementation, contracts,
draft handling, event bindings and tests live in
`modules/communications/src/features/provider-accounts/`. Organization scope does
not make the host or this delivery package the domain owner. Query/action IDs and
Phoenix credential/grant authority remain unchanged. Registration now uses
Communications-owned DTO admission and draft/action handling; the remote supplies
only the scoped query/action port. Validation patches update the existing form
instead of triggering a new query. Detail now owns DTO admission, grant drafts,
pending states, receipt checks and read-only recovery within the same feature.
Actions carry the observed account and credential versions; grant revocation also
carries the observed grant version. Phoenix rejects stale snapshots at admission
and checks that a revoked grant belongs to the selected account. These checks do
not constitute atomic external-effect execution or a global exactly-once guarantee.
The directory now uses the bounded Communications-owned read model in
`Cadence.Reads.Comms.ProviderAccountDirectory`. Its Vue layout owns classes,
labels and links, rather than accepting arbitrary presentation attributes.
The host composes it through `organization.page` version 1 without a frontend
application installation or release; this remote remains a public-entry adapter.
Registration also uses host composition through `comms.provider-account-registration`.
Its `validate`/`save` port is bound to the server-issued page token, organization,
user and path. Refresh preserves hidden identities; leaving rotates the instance.
The domain producer/workflow lives in `Cadence.GroundNetworks.ProviderAccountRegistration`;
the historical backend entry delegates. Save consumes the instance before effects,
including uncertain or partial results, without claiming global exactly-once behavior.
Detail now uses `comms.provider-account-detail` in the same slot. The host binds
resource identity to the account URL and checks it again before every command/read.
`Cadence.Reads.Comms.ProviderAccountDetail` owns the scoped read; credential/grant
commands and observed-version admission live in `Cadence.GroundNetworks.ProviderAccountOperations`.
The legacy producer/action adapter delegates to these owners. Effect requests use
an increasing page-local sequence: duplicates cannot repeat effects, and uncertain
outcomes lock further mutations while retaining read-only refresh. Refresh preserves
the grant draft and does not clear the lock. These guards are not cross-session
idempotency or atomic external-effect execution.

`Cadence.Applications.OrganizationAdmin` registers the application in Cadence core, alongside
its query and action providers. The web app authenticates transport requests and adapts session
and delivery operations. Core does not conditionally load an application from `cadence_web`.

The frontend host owns sign-in, invitation, no-organization, and admin-mode screens. Their native
forms submit to Phoenix session endpoints. Organization switching and administrative eligibility
remain enforced on the server. Invitation mail uses a configured delivery port so domain actions
do not depend on the Phoenix endpoint or mail implementation.

See [host architecture](../../docs/host-architecture.md) for composition and validation boundaries.
