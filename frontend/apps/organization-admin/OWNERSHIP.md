# Organization administration ownership

This remote renders organization and platform administration screens. Shared controls and
styles come from `@cadence/ui` and `@cadence/design-tokens`.

`Cadence.Applications.OrganizationAdmin` registers the application in Cadence core, alongside
its query and action providers. The web app authenticates transport requests and adapts session
and delivery operations. Core does not conditionally load an application from `cadence_web`.

The frontend host owns sign-in, invitation, no-organization, and admin-mode screens. Their native
forms submit to Phoenix session endpoints. Organization switching and administrative eligibility
remain enforced on the server. Invitation mail uses a configured delivery port so domain actions
do not depend on the Phoenix endpoint or mail implementation.

See [host architecture](../../docs/host-architecture.md) for composition and validation boundaries.
