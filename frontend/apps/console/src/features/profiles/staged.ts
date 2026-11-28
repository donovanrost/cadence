import type { MissionId } from "@/api/index.ts";
import { computed, type Ref } from "vue";
import { useConfigState, who, type ChangeSet } from "@/features/changes/index.ts";
import { useSession } from "@/shell";
import { fieldText, type ProfileField } from "./detail.ts";

/**
 * A profile field already staged in the open change set (Profile.md States: Conflict). `by` is
 * the author in a line (U25, #308): a person by name, "Cadence", a service identity marked; null
 * for a person with no name, whose name drops from the sentence.
 */
export type StagedField = Readonly<{
  path: string;
  by: string | null;
  mine: boolean;
  value: unknown;
}>;

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
          by: who(change.author),
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
export const stagedText = (f: ProfileField, s: StagedField) => {
  const value = fieldText({ ...f, value: s.value });
  if (s.mine) return `You staged ${value}`;
  return s.by ? `${s.by} staged ${value}` : `Staged ${value}`;
};

/** Stage's reason while another author's value for a dirty field stands (U25: no name drops). */
export const stagedConflict = (s: StagedField, label: string) =>
  s.by
    ? `${s.by} already staged ${label}. Resolve it on Staged changes first.`
    : `Already staged in the open change set: ${label}. Resolve it on Staged changes first.`;
