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

/** Capabilities effective in `organization` (the URL's org), as computed by the server. */
export function organizationCapabilities(
  _session: Readonly<Session>,
  organization: Readonly<SessionOrganization>,
): ReadonlySet<string> {
  return new Set(organization.capabilities);
}

/** Org administration (people, missions, provider accounts, settings, audit). */
export function canAdministerOrganization(
  session: Readonly<Session>,
  organization: Readonly<SessionOrganization>,
): boolean {
  const caps = organizationCapabilities(session, organization);
  return caps.has("organization_admin") || caps.has("platform_admin");
}
