import { inject, provide, type InjectionKey } from "vue";
import type { Session, SessionOrganization } from "@/api/session.ts";

const sessionKey: InjectionKey<Readonly<Session>> = Symbol("apogee.session");

/** Called once by App.vue after the bootstrap resolves. */
export function provideSession(session: Readonly<Session>) {
  provide(sessionKey, session);
}

/** The decoded bootstrap snapshot. Only available inside the booted shell. */
export function useSession(): Readonly<Session> {
  const session = inject(sessionKey);
  if (!session) throw new Error("useSession() called outside the booted console shell");
  return session;
}

export function hasCapability(session: Readonly<Session>, capability: string): boolean {
  return session.capabilities.includes(capability);
}

/**
 * Capabilities effective in `organization` (the URL's org). The bootstrap's `capabilities` are
 * for the session's current organization only; for any other org they are derived from the
 * membership role until the API sends per-organization capabilities. UI gating only: the server
 * enforces every action.
 */
export function organizationCapabilities(
  session: Readonly<Session>,
  organization: Readonly<SessionOrganization>,
): ReadonlySet<string> {
  if (organization.id === session.current_organization_id) return new Set(session.capabilities);
  const derived = new Set<string>();
  if (organization.role === "organization_admin") derived.add("organization_admin");
  if (session.capabilities.includes("platform_admin")) derived.add("platform_admin");
  return derived;
}

/** Org administration (people, missions, provider accounts, settings, audit). */
export function canAdministerOrganization(
  session: Readonly<Session>,
  organization: Readonly<SessionOrganization>,
): boolean {
  const caps = organizationCapabilities(session, organization);
  return caps.has("organization_admin") || caps.has("platform_admin");
}
