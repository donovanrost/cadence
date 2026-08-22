---
title: "ADR-017: Multi-Tenant Identity Federation and Credential Model"
aliases:
  [identity federation, organization idp, oidc, service identity, access token]
tags:
  [adr, architecture, authentication, authorization, identity, multi-tenancy, security]
status: proposed
created: 2026-07-25
updated: 2026-07-25
---

# ADR-017: Multi-Tenant Identity Federation and Credential Model

## Status

Proposed

This ADR extends:

- [ADR-002](002-organization-mission-scope-and-identity-model.md), which makes
  organization the tenant boundary and users global Cadence identities;
- [ADR-003](003-authorization-context-and-policy-evaluation-model.md), which
  defines `current_scope` and separates user and service actors; and
- [ADR-015](015-management-control-data-plane-architecture.md), which assigns
  identity, authorization, approval, and credential administration to the
  management plane.

This ADR decides which identities Cadence trusts, how external identities map to
internal principals, how authentication is bound to an organization, and how
sessions and access credentials constrain authorization. It does not itself
select Cedar or another policy engine. A policy engine must consume the internal
principal and authentication evidence defined here rather than interpreting
external identity-provider claims directly.

## Context

Cadence is a multi-tenant operations platform. Organizations need to integrate
their own identity providers so their administrators can control workforce
authentication, multifactor requirements, user lifecycle, and eventually
directory provisioning.

Cadence also needs non-human identities for provider integrations, automation,
mission services, and future LLM-based agents. Those identities need multiple,
rotatable credentials and bounded access tokens without being represented as
synthetic human users.

These concerns meet at the authorization boundary. A successful login or a
valid access token proves possession of an authentication mechanism. It must
not, by itself, decide what the actor may do. Cadence must still resolve a
durable internal principal, tenant scope, current lifecycle state, current
grants, policy, and domain approval requirements.

The current implementation provides a useful foundation:

- `User` is a global identity and `OrganizationMembership` carries an
  organization-specific role;
- `Scope` distinguishes `:user` and `:service` actors and carries organization
  and optional mission scope;
- local password credentials are stored separately from users;
- browser sessions are durable opaque tokens associated with a global user;
- a browser-session value selects the current organization membership; and
- `ServiceIdentity` is organization- or mission-scoped and stores the digest of
  one opaque bearer API token.

The current shape also has transitional limitations:

- there is no external identity-provider or federated-identity model;
- a browser session records a global user but no organization-specific
  authentication event or assurance;
- changing the selected organization does not require authentication through
  that organization's identity provider;
- service identity and service credential lifecycle are coupled one-to-one;
- service API tokens have no modeled expiration, audience, rotation lineage, or
  last-used state; and
- `Cadence.Auth.authenticate_api_token/2` accepts either a service API token or
  a human browser-session token through the same bearer-token entry point.

That last behavior creates token-type confusion: a secret issued for browser
session continuity can also be presented as API authorization. It must not be
part of the target security model.

## Decision

Cadence will separate durable principals, external identity links,
authenticators, authentication sessions, access tokens, delegations, and
authorization policy. Each has a distinct lifecycle and audit identity.

### 1. Separate Identity, Authentication, And Authorization

Cadence will use these terms consistently:

- **Principal** is a durable Cadence actor, such as a `User`,
  `OrganizationMembership`, or `ServiceIdentity`.
- **External identity** is an identity asserted by an organization-owned
  workforce or workload identity provider.
- **Authenticator** is a mechanism used to prove control of an identity, such
  as an OIDC transaction, client secret, private key, or workload assertion.
- **Credential** is a secret, key binding, or provider relationship used by an
  authenticator.
- **Authentication session** records that Cadence accepted an authentication
  event for a principal under stated conditions.
- **Access token** is a time- and audience-bounded credential presented to a
  Cadence API. It is not the service identity itself.
- **Delegation** is an explicit, bounded grant allowing one principal to act on
  behalf of another principal or within an approved automation envelope.
- **Authorization** decides whether the authenticated principal may perform an
  action on a resource in the current context.

Authentication establishes an internal principal. Authorization begins only
after that mapping succeeds.

### 2. Workforce Identity Providers Are Organization-Owned Trust Connections

An organization may configure one or more workforce identity providers. An
`IdentityProvider` is an organization-owned, versioned management-plane
resource with a lifecycle such as `:draft`, `:active`, or `:disabled`.

Its conceptual contract includes:

```elixir
%IdentityProvider{
  identity_provider_id: binary(),
  organization_id: binary(),
  protocol: :oidc,
  issuer: binary(),
  client_id: binary(),
  credential_reference: binary() | nil,
  claim_mapping_version: pos_integer(),
  lifecycle_state: :draft | :active | :disabled,
  configuration_version: pos_integer()
}
```

OIDC Authorization Code flow is the initial workforce federation protocol.
SAML may be added through a separate protocol adapter when customer demand
requires it. Protocol adapters must produce the same internal authentication
result and must not leak protocol-specific claims into application contexts.

Provider activation must validate and pin the expected issuer, client,
redirect URI, allowed signing algorithms, discovery metadata, and key source.
Authorization responses must be bound to the initiating browser using `state`,
`nonce`, PKCE, and exact issuer validation. Tokens must be validated for
signature, issuer, audience, time window, and transaction binding before any
identity lookup occurs.

An organization-controlled issuer URL is also an outbound-network trust input.
Discovery, JWKS, token, user-info, and logout requests must use a restricted
HTTP client policy that:

- requires TLS outside explicitly controlled development environments;
- rejects loopback, link-local, metadata-service, and private-network targets
  unless an operator-controlled deployment policy explicitly permits them;
- revalidates redirect targets instead of following arbitrary redirects;
- applies response-size, connection, and request timeouts; and
- prevents one organization's provider configuration from reaching Cadence
  infrastructure or another tenant's private endpoints.

Cadence HTTP integrations will use the existing `Req` library. Client secrets,
private keys, and refresh tokens are secret references, not ordinary metadata.

Provider configuration changes require organization-administrator
authorization, append-only audit evidence, pre-activation testing, and a
recoverable rollback path. Disabling a provider denies new authentication and
invalidates its active Cadence authentication bindings according to the
revocation rules below.

### 3. External Subjects Map To Stable Internal Users

A `FederatedIdentity` links an external subject to a global Cadence user:

```elixir
%FederatedIdentity{
  federated_identity_id: binary(),
  identity_provider_id: binary(),
  organization_id: binary(),
  external_subject: binary(),
  user_id: binary(),
  lifecycle_state: :active | :disabled,
  linked_at: DateTime.t(),
  last_authenticated_at: DateTime.t() | nil
}
```

The stable lookup key is `(identity_provider_id, external_subject)`. For OIDC,
the configured provider pins the issuer and `external_subject` is the validated
`sub` claim. The pair of OIDC `iss` and `sub` is the external identity; email,
username, display name, and group names are attributes.

Cadence will not automatically link or merge users because email addresses
match. A new external identity may be attached to an existing global user only
through one of these accountable flows:

- the already-authenticated user explicitly links the identity;
- the identity claims a pending invitation for the same organization through a
  transaction bound to that invitation; or
- an authorized administrator or provisioning connection establishes the link
  under a reviewed conflict policy.

An email match may inform those flows, but it is never sufficient proof. The
current global unique-email constraint is an account-management constraint, not
an external identity key, and must not be used as an implicit federation join.

A user may have multiple federated identities, including identities from
different organizations. Disabling one link does not delete the global user or
unrelated organization memberships.

### 4. Authentication Does Not Create Authorization By Implication

Successful workforce authentication does not automatically create an active
organization membership or administrator role.

Initial federation will use one of these explicit enrollment sources:

- an existing active organization membership;
- a pending organization invitation; or
- a provisioning record created by an authorized organization administrator.

If just-in-time enrollment is later supported, it may create only the
least-privileged configured membership or a pending membership. It must never
infer organization-administrator, mission-administrator, command approval, or
automation authority from an ungoverned claim.

SCIM provisioning is separate from interactive authentication. When added, it
may create, update, suspend, or deprovision users and groups, but it will map
stable external object identifiers through versioned Cadence provisioning
rules. External group names and transient ID-token group claims do not become
roles or Cedar parents directly.

An external-group-to-Cadence-role mapping is itself a versioned,
organization-owned management-plane resource. Its activation, retirement, and
effects are authorized and audited.

### 5. Ordinary Human Sessions Are Bound To One Organization

Every ordinary tenant human session, whether federated or local, is bound to
exactly one organization. A federated workforce authentication event therefore
establishes a Cadence session for the organization that owns the accepted trust
connection. The session records normalized authentication evidence, not the raw
identity-provider token:

```elixir
%AuthenticationSession{
  authentication_session_id: binary(),
  user_id: binary(),
  organization_id: binary() | nil,
  organization_membership_id: binary() | nil,
  identity_provider_id: binary() | nil,
  federated_identity_id: binary() | nil,
  authentication_method: :oidc | :local | :recovery,
  authenticated_at: DateTime.t(),
  assurance: %{mfa: boolean(), acr: binary() | nil, amr: [binary()]},
  expires_at: DateTime.t(),
  revocation_epoch: non_neg_integer()
}
```

Provider-specific `acr` and `amr` claims must be mapped through the active
provider configuration into normalized Cadence assurance. An unknown or absent
claim fails closed when a policy requires a particular assurance level.

Selecting an organization is not proof of authentication for that
organization. Changing from one organization to another requires a new
authentication transaction acceptable to the target organization, followed by
session rotation or replacement. A login asserted by Organization A must not
authorize access to Organization B merely because the same global user has
memberships in both.

Platform administration and emergency recovery may use a platform-scoped
session with no organization membership. Such access is distinct from an
ordinary organization session and is subject to stronger controls, shorter
lifetimes, explicit audit, and deployment-level alerting.

Cadence owns its session after federation succeeds. Upstream ID tokens and
access tokens are not reused as Cadence browser-session secrets. Session
expiration, idle timeout, reauthentication, provider disablement, membership
revocation, and user disablement are enforced from current Cadence state.

High-impact operations may require step-up authentication or a maximum
authentication age even when the surrounding session remains valid. The
resulting assurance and authentication time become request context for policy
evaluation and durable approval evidence.

### 6. Tenant Human Authorization Uses Membership As The Effective Principal

For organization-scoped human operations, the effective authorization
principal is the active `OrganizationMembership`, with the global `User`
retained as the human actor identity for account management and audit.

This produces distinct tenant principals when one human belongs to multiple
organizations and makes cross-organization role leakage harder to express.

The intended policy-principal mapping is:

| Operation | Effective principal |
|-----------|---------------------|
| Organization or mission human operation | `OrganizationMembership` |
| Platform-wide administration | `User` |
| Service or automation operation | `ServiceIdentity` |

`current_scope` remains the application boundary. It will additionally carry
or reference the accepted authentication session and normalized authentication
evidence. Callers cannot supply principal IDs, organization IDs, assurance, or
provider IDs as trusted request parameters.

### 7. Service Identities Are Durable Non-Human Principals

A `ServiceIdentity` is a durable organization- or mission-scoped principal. It
is not an API token, OAuth client, process PID, synthetic user, or human
membership.

Service identities are appropriate for:

- provider integrations and inbound webhooks;
- mission automation and scheduling;
- CI/CD or configuration publication;
- machine-to-machine API clients;
- procedure execution and verification; and
- LLM-based agents acting within an approved automation grant.

Service identities may have multiple authenticators and credentials. Disabling
a service identity disables every associated credential, access token,
delegation, and new authorization decision. Deleting a credential does not
delete the identity or its audit history.

Human workforce federation and workload federation are separate trust
connections even when both use OIDC tokens from the same vendor. A workforce
ID token must not authenticate a service identity, and a workload assertion
must not create a human session.

Future workload federation may validate an external workload assertion against
an organization-owned `WorkloadIdentityProvider` and map exact issuer,
audience, subject, and other allowlisted conditions to one existing
`ServiceIdentity`. Cadence may then mint a short-lived Cadence access token or
perform a standards-compatible token exchange. The external workload token is
not accepted by unrelated Cadence API authenticators.

An agent acting on behalf of a human remains a `ServiceIdentity` principal with
an explicit delegation or automation grant. It does not inherit a human session
or raw workforce token.

### 8. Credentials And Access Tokens Have Independent Lifecycles

Service credentials will move out of `service_identities` into a one-to-many
credential inventory. A conceptual credential record includes:

```elixir
%ServiceCredential{
  service_credential_id: binary(),
  service_identity_id: binary(),
  kind: :opaque_secret | :public_key | :workload_federation,
  secret_digest_or_key_reference: binary(),
  token_hint: binary() | nil,
  audience: binary(),
  issued_at: DateTime.t(),
  expires_at: DateTime.t(),
  last_used_at: DateTime.t() | nil,
  rotated_from_id: binary() | nil,
  revoked_at: DateTime.t() | nil
}
```

Raw symmetric credentials and tokens are returned only at issuance. Cadence
stores a digest or managed-secret reference, never the recoverable raw value.
Credential hints are non-secret and must not provide enough material to
authenticate.

Every API credential or access token has:

- an unambiguous token class;
- an issuer and intended audience;
- an organization and optional mission ceiling;
- issuance and mandatory expiration times;
- a unique audit identifier;
- explicit revocation state or bounded revocation latency; and
- rotation behavior that permits a short, observable overlap window.

Browser-session tokens, service credentials, service access tokens, personal
access tokens, invitation tokens, and recovery tokens use distinct formats and
distinct authentication entry points. A browser-session token is accepted only
from the protected browser-session mechanism and is never a general API bearer
token.

The effective authority of an API request is the intersection of:

```text
active internal principal
AND active credential, token, delegation, or automation-grant bounds
AND token audience, organization, mission, and time bounds
AND current authorization policy
AND current domain, approval, and safety invariants
```

A token can attenuate authority but cannot grant authority absent from the
current principal and policy. Roles, Cedar parents, capabilities, and mutable
organization membership are not copied into a long-lived token as the sole
source of truth.

Opaque reference tokens are the default for the initial centralized Cadence
deployment because they support current-state validation and immediate
revocation. A future self-contained JWT access-token profile requires a
separate decision covering signing-key custody and rotation, exact claim
validation, audience isolation, replay resistance, introspection, revocation
latency, and multi-service trust. Accepting a signed JWT does not remove the
need to validate current identity and grant state at effectful boundaries.

Long-running automation must use rotation, a renewable authenticator, or
workload federation rather than a non-expiring bearer token. High-impact
production integrations should use short-lived or sender-constrained tokens
when supported. Possession of a bearer token is treated as possession of its
full bounded authority until the token expires or Cadence observes revocation.

### 9. Policy Engines Consume Cadence Entities, Not Raw Claims

The authorization engine receives only validated, Cadence-owned inputs:

- an internal principal;
- an application-owned action identifier;
- an internal resource and tenant hierarchy;
- a bounded entity slice built from current durable state; and
- normalized request context such as authentication age, MFA assurance,
  delegation, network posture, or change-request evidence.

If Cedar is adopted, tenant human requests use an
`OrganizationMembership::<id>` principal, platform requests use a
`User::<id>` principal, and machine requests use a
`ServiceIdentity::<id>` principal. External subjects, email domains, group
names, and arbitrary ID-token claims are not Cedar principal IDs and do not
enter policy context without normalization through a trusted mapping.

Authentication and token validation occur before Cedar evaluation. Cedar does
not validate OIDC tokens, client secrets, signatures, expiration, or session
cookies. Cedar may require normalized authentication properties such as recent
MFA for an action.

IdP configuration, federated-identity linking, provisioning mappings,
credential issuance, token rotation, delegation, and revocation are themselves
authorized management-plane actions. Tenant-defined policy may narrow tenant
authority but may not override platform tenant-isolation, credential, or
break-glass guardrails.

### 10. Revocation Is Evaluated From Current State

Cadence will define revocation effects by the record being changed:

| Revoked or disabled record | Required effect |
|----------------------------|-----------------|
| Identity provider | Deny new logins and revoke or invalidate sessions established through it |
| Federated identity | Revoke sessions established through that link |
| Organization membership | Deny organization access and revoke its sessions and personal tokens |
| Global user | Revoke all human sessions and deny all user-backed authorization |
| Service identity | Deny all credentials, tokens, delegations, and new service authorization |
| One service credential | Deny that credential and tokens derived from it where linkage is available |
| Delegation or automation grant | Deny new delegated actions without granting new cleanup authority |
| Policy bundle or role grant | Apply the new decision to every new authorization request |

Authorization caches must be bounded by a revocation epoch, policy version, or
equivalent invalidation mechanism. High-impact writes cannot rely indefinitely
on scope or authorization data captured at login.

Revocation prevents new authority. It does not erase already-observed external
effects. Control-plane reconciliation may retain narrowly defined authority to
observe, record, compensate, or safely converge an operation that was already
released, but it may not initiate unrelated work under the revoked grant.

### 11. Authentication And Credential Events Are Durable Audit Evidence

Cadence will audit at least:

- identity-provider configuration, test, activation, disablement, and rollback;
- federated-identity link, conflict, disablement, and relink;
- successful and failed authentication outcomes without sensitive claims;
- session issuance, organization binding, step-up, rotation, expiration, and
  revocation;
- provisioning and group-mapping changes;
- service-identity creation, scope change, disablement, and recovery;
- credential and access-token issuance, rotation, last-used update, and
  revocation; and
- the internal principal, credential or session identifier, organization,
  mission, delegation, policy version, and authentication evidence used for an
  effectful authorization decision.

Raw passwords, client secrets, session tokens, access tokens, authorization
codes, private keys, ID tokens, and refresh tokens must never appear in logs,
operational events, policy input, error messages, or general metadata.

### 12. Bootstrap And Recovery Do Not Depend On A Tenant IdP

Cadence must retain a platform-owned recovery path for customer IdP outage,
misconfiguration, certificate or signing-key failure, and accidental
administrator deprovisioning.

Recovery identities are not ordinary organization administrators. They are
platform principals with narrowly defined actions, strong authenticators,
short sessions, explicit invocation reason, prominent audit, and alerting. An
organization may also configure recovery administrators, but their recovery
flow must not permit bypassing platform tenant isolation or silently weakening
the organization's active IdP policy.

The current environment-backed bootstrap password is transitional setup
machinery, not the final production break-glass design.

### 13. Boundary And Routing Consequences

Federation and credential administration belong to the management plane.
Control- and data-plane modules consume approved internal principals and exact
authorization evidence; they do not parse external assertions or select an
identity provider.

When implemented in Phoenix:

- workforce login start and callback routes belong in the standard `:browser`
  pipeline without `:require_authenticated_scope`, because they establish or
  replace authentication and must support both initial login and
  organization-switch reauthentication;
- IdP, federation-link, provisioning, and credential-management routes belong
  under `[:browser, :require_authenticated_scope]` plus the appropriate
  organization-admin `live_session`, because they mutate tenant security
  configuration;
- token issuance or exchange endpoints belong in the `:api` pipeline with a
  purpose-specific client or workload authentication pipeline, because they
  create access rather than consume an existing Cadence access token; and
- protected API resources continue to require `:authenticated_api`, but its
  authenticator must accept only documented API token classes and must never
  fall back to browser sessions.

Redirect destinations captured before authentication must be local,
allowlisted paths. IdP-provided or caller-provided arbitrary return URLs are not
accepted.

## Threat Model And Required Failure Behavior

The implementation must fail closed for at least these threats:

- malicious or mistaken IdP endpoint configuration causing SSRF;
- authorization-server mix-up or assertion injection across organizations;
- account takeover through automatic email matching;
- stale group claims retaining authority after deprovisioning;
- cross-organization access through a global user session;
- browser-session and API-token type confusion;
- bearer-token disclosure and replay;
- stale self-contained token claims after role, grant, or policy revocation;
- workload assertions being accepted as workforce identities or vice versa;
- agent delegation being interpreted as human impersonation;
- signing-key rotation, clock skew, or IdP outage causing ambiguous acceptance;
  and
- tenant IdP misconfiguration locking out all recovery actors.

Malformed, ambiguous, unknown-provider, unknown-subject, wrong-audience,
wrong-organization, expired, revoked, or assurance-insufficient credentials are
reported as unauthenticated or forbidden without exposing tenant or account
existence.

## Consequences

### Positive

- Organizations can control workforce authentication without becoming the
  direct source of Cadence authorization policy.
- One human can participate in multiple organizations without allowing one
  organization's assertion to authorize another organization.
- Service identities remain durable and auditable while credentials become
  independently rotatable and revocable.
- Browser sessions, service credentials, and access tokens cannot be confused
  by a shared bearer-token fallback.
- Cedar or another policy engine receives stable internal entities and
  normalized authentication evidence.
- Workload federation and LLM agents fit the same service-principal model
  without receiving human tokens.

### Negative

- Organization switching may require a visible reauthentication transaction.
- Identity-provider configuration becomes a security-sensitive outbound
  network surface.
- Global users, organization memberships, federated identities, sessions,
  authenticators, credentials, tokens, and delegations are separate records
  with coordinated lifecycle rules.
- Immediate revocation favors centralized opaque-token validation and adds a
  dependency on the authentication data store or a bounded cache.
- Enterprise group provisioning requires governed mappings rather than direct
  use of convenient token claims.

### Constraints Introduced

- No external subject, email address, or group claim is a Cadence authorization
  principal by itself.
- No tenant workforce assertion can authenticate a service identity.
- No browser session token is accepted as an API bearer token.
- No access token grants more authority than the current principal, grants,
  policy, and domain invariants allow.
- No ordinary federated human session is valid across organizations without a
  target-organization authentication event.
- No production service bearer credential is non-expiring in the target model.

## Initial Adoption Sequence

1. Accept the vocabulary and lifecycle boundaries in this ADR before freezing
   the authorization-engine entity schema.
2. Split browser-session authentication from service API authentication and
   introduce unambiguous token classes without changing user-facing login.
3. Move service credentials to a one-to-many inventory with mandatory expiry,
   independent revoke/rotate operations, audit identifiers, and last-used
   state.
4. Add organization-owned `IdentityProvider`, `FederatedIdentity`, and
   organization-bound `AuthenticationSession` records.
5. Implement one OIDC workforce provider vertical using `Req`, an
   organization-scoped login start, strict callback validation, explicit
   identity linking, and Cadence-owned sessions.
6. Extend `current_scope` with authentication-session evidence and make
   organization membership the effective tenant human policy principal.
7. Pilot the external policy-engine boundary against internal principals and
   normalized authentication context; do not make OIDC claims policy inputs.
8. Replace non-expiring service tokens with rotatable, audience-bound opaque
   credentials or short-lived access-token issuance.
9. Add workload federation and token exchange for selected service-identity
   use cases before giving autonomous agents production authority.
10. Add SCIM and governed external-group mapping when customer lifecycle needs
    justify it; add SAML only through the common federation result contract.
11. Replace transitional bootstrap access with a production recovery design and
    exercise IdP outage, key rotation, revocation, and tenant-lockout drills.

## Open Questions

1. Should Cadence retain globally unique user email addresses after federation,
   or move verified contact addresses into a separate one-to-many table?
2. Which normalized authentication assurance levels and maximum ages are
   required for command approval, policy publication, credential issuance, and
   agent-grant approval?
3. Does the first service-token migration need a full OAuth-compatible token
   endpoint, or is a narrower Cadence credential-exchange contract sufficient?
4. Which production integrations require mTLS, DPoP, or another
   proof-of-possession mechanism rather than bounded bearer tokens?
5. How should customer-managed keys and secrets integrate with deployment KMS
   or secret-manager facilities without making Cadence metadata a secret store?
6. Which IdP changes require a second administrator, delayed activation, or
   platform review to prevent tenant lockout?
7. What is the first customer requirement that justifies SCIM or SAML beyond
   the initial OIDC and invitation-based model?
8. How are active organization sessions surfaced and revoked by users and
   organization administrators?

## Deferred Decisions

This ADR does not decide:

- the concrete authorization policy engine or policy language;
- the final Cedar schema or policy-administration user experience;
- the final OIDC, SAML, or SCIM library selection;
- cross-organization resource sharing or trust;
- mission-supplied executable-agent sandboxing;
- the final distributed access-token format; or
- a general-purpose public OAuth authorization-server product.

## Standards And Guidance

- [OpenID Connect Core 1.0](https://openid.net/specs/openid-connect-core-1_0.html)
- [RFC 9700: Best Current Practice for OAuth 2.0 Security](https://www.rfc-editor.org/rfc/rfc9700.html)
- [RFC 7644: System for Cross-domain Identity Management Protocol](https://www.rfc-editor.org/rfc/rfc7644.html)
- [RFC 7662: OAuth 2.0 Token Introspection](https://www.rfc-editor.org/rfc/rfc7662.html)
- [RFC 8693: OAuth 2.0 Token Exchange](https://www.rfc-editor.org/rfc/rfc8693.html)
- [RFC 8705: OAuth 2.0 Mutual-TLS](https://www.rfc-editor.org/rfc/rfc8705.html)
- [RFC 9449: OAuth 2.0 Demonstrating Proof of Possession](https://www.rfc-editor.org/rfc/rfc9449.html)
- [NIST SP 800-63B-4: Authentication and Authenticator Management](https://pages.nist.gov/800-63-4/sp800-63b.html)
- [NIST SP 800-63C-4: Federation and Assertions](https://pages.nist.gov/800-63-4/sp800-63c.html)

## See Also

- [ADR-002: Organization, Mission, and Identity Scope Model](002-organization-mission-scope-and-identity-model.md)
- [ADR-003: Authorization Context and Policy Evaluation Model](003-authorization-context-and-policy-evaluation-model.md)
- [ADR-004: Activation Authorization and Approval Policy](004-activation-authorization-and-approval-policy.md)
- [ADR-005: Runtime Partitioning and Workload Isolation](005-runtime-partitioning-and-workload-isolation.md)
- [ADR-011: Command Staging, Queueing, and Release Lifecycle](011-command-staging-queueing-and-release-lifecycle.md)
- [ADR-015: Three-Plane Architecture](015-management-control-data-plane-architecture.md)
