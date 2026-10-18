import { readHostContext } from "../../../shell/host-snapshot";
import { record, string } from "../../../shell/snapshot-readers";

export function readWorkspaceBootstrap(value: unknown) {
  if (!record(value) || value.version !== 1) throw Error("Unavailable contact workspace");
  const actorId = string(value.actor_id);
  const organizationId = string(value.organization_id);
  const missionId = string(value.mission_id);
  const context = readHostContext(value.context);
  if (
    !actorId ||
    !organizationId ||
    !missionId ||
    context.user?.user_id !== actorId ||
    context.organization?.organization_id !== organizationId ||
    context.mission?.mission_id !== missionId
  )
    throw Error("Different contact workspace identity");
  return { actorId, organizationId, missionId, context };
}
export type WorkspaceBootstrap = ReturnType<typeof readWorkspaceBootstrap>;
export const workspaceBase = (mission: string) =>
  `/missions/${encodeURIComponent(mission)}/ops/contact-workspace`;

/** Map domain destinations into this experiment; all other destinations stay native. */
export function workspaceDestination(href: string, mission: string, origin: string): string | null {
  const url = new URL(href, origin);
  if (url.origin !== new URL(origin).origin || url.username || url.password) return null;
  const canonical = `/missions/${encodeURIComponent(mission)}/ops/contacts`;
  const base = workspaceBase(mission);
  const path = url.pathname;
  const recordPath = (prefix: string) =>
    path.startsWith(`${prefix}/records/`) &&
    path.slice(`${prefix}/records/`.length).length > 0 &&
    !path.slice(`${prefix}/records/`.length).includes("/");
  if (path === canonical || recordPath(canonical))
    return base + path.slice(canonical.length) + url.search + url.hash;
  if (path === base || recordPath(base)) return path + url.search + url.hash;
  return null;
}
