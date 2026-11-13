import { recordOf } from "@/api";
import type { Target } from "./templates.ts";

/** Target form state, kept as text until saved. */
export type TargetDraft = {
  kind: "profile" | "plane" | "spacecraft_ids";
  profileId: string;
  plane: string;
  ids: string;
};

export function draftFromTarget(t: unknown): TargetDraft {
  const empty: TargetDraft = { kind: "profile", profileId: "", plane: "", ids: "" };
  const r = recordOf(t);
  if (r === null) return empty;
  if (r.kind === "plane" && typeof r.plane === "number")
    return { ...empty, kind: "plane", plane: String(r.plane) };
  if (r.kind === "spacecraft_ids" && Array.isArray(r.spacecraft_ids))
    return {
      ...empty,
      kind: "spacecraft_ids",
      ids: r.spacecraft_ids.filter((x): x is string => typeof x === "string").join(", "),
    };
  if (r.kind === "profile" && typeof r.spacecraft_type_id === "string")
    return { ...empty, profileId: r.spacecraft_type_id };
  return empty;
}

export function targetFromDraft(
  d: TargetDraft,
): Readonly<{ ok: true; target: Target } | { ok: false; message: string }> {
  switch (d.kind) {
    case "profile":
      return d.profileId
        ? { ok: true, target: { kind: "profile", spacecraft_type_id: d.profileId } }
        : { ok: false, message: "Choose a profile." };
    case "plane":
      return /^\d+$/.test(d.plane.trim())
        ? { ok: true, target: { kind: "plane", plane: Number(d.plane.trim()) } }
        : { ok: false, message: "Enter a plane number." };
    case "spacecraft_ids": {
      const ids = [
        ...new Set(
          d.ids
            .split(",")
            .map((x) => x.trim())
            .filter(Boolean),
        ),
      ];
      return ids.length > 0
        ? { ok: true, target: { kind: "spacecraft_ids", spacecraft_ids: ids } }
        : { ok: false, message: "List at least one spacecraft id." };
    }
  }
}

/** A JSON object document (or empty), for prefilling forms from `unknown` documents. */
export function asRecord(value: unknown): Readonly<Record<string, unknown>> {
  return recordOf(value) ?? {};
}
