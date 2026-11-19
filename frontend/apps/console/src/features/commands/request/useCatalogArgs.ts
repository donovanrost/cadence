import type { MissionId } from "@/api/index.ts";
import { computed, type Ref } from "vue";
import { useRemoteQuery } from "@/api/index.ts";
import { fetchCommand, type CommandArgument } from "../api.ts";
import type { Group } from "../groups/show.ts";

/**
 * The catalog arguments (units, ranges, order) of the group's commands that some target sends with
 * its own values (ux C2), read once per command; the others aren't fetched.
 */
export function useCatalogArgs(missionId: Ref<MissionId>, group: Ref<Group>) {
  const read = useRemoteQuery(
    computed(() => {
      const ids = [
        ...new Set(
          group.value.commands
            .filter((c) => (c.per_target ?? []).length > 0)
            .map((c) => c.command_id),
        ),
      ];
      return ids.length ? { m: missionId.value, ids } : null;
    }),
    async (k, signal) => {
      const reads = await Promise.all(k.ids.map((id) => fetchCommand(k.m, id, signal)));
      const map = new Map<string, readonly CommandArgument[]>();
      reads.forEach((r, i) => {
        const id = k.ids[i];
        if (r.ok && id && r.value.command) map.set(id, r.value.command.arguments);
      });
      return { ok: true as const, value: map };
    },
  );
  return (commandId: string): readonly CommandArgument[] => {
    const s = read.state.value;
    return s.status === "ready" ? (s.value.get(commandId) ?? []) : [];
  };
}
