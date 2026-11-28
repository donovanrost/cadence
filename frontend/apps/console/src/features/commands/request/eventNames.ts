import type { SpacecraftName } from "@/features/scheduling/names.ts";
import type { EventTargets } from "../groups/words.ts";
import type { Group, GroupEvent } from "../groups/show.ts";

/**
 * #795: what the log needs to name the spacecraft its events mention (a failed member, a HOLD's
 * targets), built for those ids only. A target on the group's first page names itself; any other
 * comes from the mission's names read. Command names come from the group's commands by position.
 */
export function eventTargets(
  events: readonly GroupEvent[],
  group: Pick<Group, "targets" | "commands">,
  nameOf: (id: string) => SpacecraftName | null,
): EventTargets {
  const ids = new Set<string>();
  for (const e of events) {
    if (e.payload?.spacecraft_id) ids.add(e.payload.spacecraft_id);
    for (const id of e.payload?.evidence?.spacecraft_ids ?? []) ids.add(id);
  }
  const shown = new Map(group.targets.map((t) => [t.spacecraft_id, t.name] as const));
  const members = group.commands.map((c) => ({ position: c.position, command_name: c.name }));
  return [...ids].map((id) => ({
    spacecraft_id: id,
    name: shown.get(id) ?? nameOf(id)?.name ?? null,
    members,
  }));
}
