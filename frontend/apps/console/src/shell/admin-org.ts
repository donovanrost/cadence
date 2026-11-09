import { ref, watch, type Ref } from "vue";
import { request } from "@/api/http.ts";
import { sessionReader, type Session } from "@/api/session.ts";
import type { ConsoleScope } from "./scope.ts";

const TRIED = "apogee.adminOrgTried";

function tried(slug: string): boolean {
  try {
    return sessionStorage.getItem(`${TRIED}:${slug}`) === "1";
  } catch {
    return false;
  }
}
function markTried(slug: string) {
  try {
    sessionStorage.setItem(`${TRIED}:${slug}`, "1");
  } catch {
    // Without storage the guard is per page load only; the reload below still happens once.
  }
}

/**
 * qa #15: a platform admin in admin mode has no memberships, so the session lists no orgs. When
 * the URL names an org the session doesn't know, select it as the session's current org
 * (PUT /session/organization {organization_slug}) and reload once so the bootstrap includes it.
 * A 404 (unknown slug or not allowed) falls through to the normal not-found screen.
 */
export function useAdminOrgSelect(scope: Readonly<Ref<ConsoleScope>>, session: Readonly<Session>) {
  const switching = ref<string | null>(null);
  const eligible = session.admin_mode && session.capabilities.includes("platform_admin");
  watch(
    scope,
    async (s) => {
      if (!eligible || s.kind !== "unknown-organization" || tried(s.slug)) return;
      markTried(s.slug);
      switching.value = s.slug;
      const result = await request("/session/organization", sessionReader, {
        method: "PUT",
        body: { organization_slug: s.slug },
      }).catch(() => null);
      if (result?.ok) window.location.reload();
      else switching.value = null;
    },
    { immediate: true },
  );
  return { switching };
}
