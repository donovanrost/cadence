# Organization Admin federation ownership

This remote is the first-party renderer boundary for post-auth organization and
platform administration surfaces. Its Phoenix counterpart remains authoritative
for scope, authorization, validation, forms, CSRF, durable state, navigation, and
LiveView events.

## Frozen Vue closure

The following entry components are copied from the pre-batch surface family:

- `OrganizationHome.vue`
- `ProviderAccountListPage.vue`
- `ProviderAccountNew.vue`
- `ProviderAccountShow.vue`
- `NotificationsPage.vue`
- `NotificationsBell.vue`
- `AdminHome.vue`
- `AdminRuntime.vue`
- `AdminOrganizationListPage.vue`
- `AdminOrganizationNew.vue`
- `AdminOrganizationShow.vue`
- `AdminOrganizationInvite.vue`

Their local `src/ui/**` dependencies, `ProviderAccountCards.vue`,
`OrganizationStats.vue`, `RecentMissions.vue`, `NotificationsPanel.vue`, and
`StatusBadge.vue` are owned here as well. No module imports from
`apps/cadence_web/assets/vue`.

## Deliberate host-owned flows

Sign-in, invitation acceptance, no-organization bootstrap, and admin-mode
transitions remain Phoenix/host-owned. The copied notification and admin
surfaces emit bounded events to those Phoenix handlers; they do not become an
authorization, session, or persistence boundary.

Existing LiveViews and local Vue mounts remain compatibility wrappers until a
central composition change is separately authorized.
