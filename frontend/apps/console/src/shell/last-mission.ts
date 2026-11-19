import type { Session } from "@/api/session.ts";

const KEY = "apogee.lastMission";

export type MissionRef = Readonly<{ org: string; mission: string }>;

export function rememberMission(ref: MissionRef) {
  try {
    localStorage.setItem(KEY, `${ref.org}/${ref.mission}`);
  } catch {
    // Storage unavailable (private mode, blocked): remembering is a convenience only.
  }
}

/** Last visited mission if the session still grants it, else the first available one. */
export function defaultMission(session: Readonly<Session>, orgSlug?: string): MissionRef | null {
  let stored: string | null = null;
  try {
    stored = localStorage.getItem(KEY);
  } catch {
    stored = null;
  }
  const [org, mission] = stored?.split("/") ?? [];
  const orgs = orgSlug
    ? session.organizations.filter((o) => o.slug === orgSlug)
    : session.organizations;
  const remembered = orgs.find((o) => o.slug === org)?.missions.find((m) => m.slug === mission);
  if (org && remembered) return { org, mission: remembered.slug };
  for (const o of orgs) {
    const first = o.missions[0];
    if (first) return { org: o.slug, mission: first.slug };
  }
  return null;
}
