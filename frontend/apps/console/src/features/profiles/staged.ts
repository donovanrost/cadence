import type { MissionId } from "@/api/index.ts";
import { computed, type Ref } from "vue";
import { actorName } from "@/api";
import { useConfigState, type ChangeSet } from "@/features/changes/index.ts";
import { useSession } from "@/shell";
import { fieldText, type ProfileField } from "./detail.ts";

/** A profile field someone already staged in the open change set (Profile.md States: Conflict). */
export type StagedField = Readonly<{ path: string; by: string; mine: boolean; value: unknown }>;

/**
 * The open set's staged values for one profile, by field path: update ops on this
 * spacecraft_profile carry `payload.changes` [{path, value}] (the server's staged value).
 */
export function stagedFields(
  set: Pick<ChangeSet, "changes"> | null,
  profileId: string,
  userId: string,
): ReadonlyMap<string, StagedField> {
  const out = new Map<string, StagedField>();
  for (const change of set?.changes ?? [])
    for (const op of change.ops) {
      if (op.kind !== "spacecraft_profile" || op.entity_id !== profileId) continue;
      const payload: unknown = op.payload;
      const changes =
        payload !== null && typeof payload === "object" && "changes" in payload
          ? payload.changes
          : null;
      if (!Array.isArray(changes)) continue;
      for (const c of changes as unknown[]) {
        if (c === null || typeof c !== "object" || !("path" in c) || typeof c.path !== "string")
          continue;
        out.set(c.path, {
          path: c.path,
          by: actorName(change.author, "Someone"),
          mine: change.author.id === userId,
          value: "value" in c ? c.value : null,
        });
      }
    }
  return out;
}

/** The shared config state (no extra fetch) narrowed to one profile's staged fields. */
export function useStagedFields(
  missionId: Readonly<Ref<MissionId>>,
  profileId: Readonly<Ref<string>>,
) {
  const config = useConfigState(missionId.value);
  const session = useSession();
  return computed(() =>
    config.state.value.status === "ready"
      ? stagedFields(config.state.value.value.change_set, profileId.value, session.user.id)
      : new Map<string, StagedField>(),
  );
}

/** The chip: `Mira K. staged 1,200` (`You staged …` for your own). */
export const stagedText = (f: ProfileField, s: StagedField) =>
  `${s.mine ? "You" : s.by} staged ${fieldText({ ...f, value: s.value })}`;
