import { decode, decoders, type Reader } from "@/api";
import type { ProfileSummary } from "@/features/profiles/index.ts";
import type { SpacecraftDirectory } from "../api.ts";
import {
  checkClashes,
  generateRows,
  manifestRows,
  MAX_BATCH,
  MAX_SCID,
  type ClashReport,
} from "./batch.ts";
import { manifestFields, readRows, type ColumnMapping } from "./manifest.ts";
import { parsePattern } from "./naming.ts";

/**
 * The Add-spacecraft draft: what the user typed, kept per mission in session storage so `×`
 * and reload don't lose work (AddSpacecraft.md). Form values stay as text; `propose` validates.
 */
export type Draft = {
  source: "profile" | "manifest";
  profileId: string;
  count: string;
  pattern: string;
  scidStart: string;
  /** Optional, one per spacecraft in order (AddSpacecraft.md step 02: "add later" by default). */
  norad: string;
  planeMode: "fill" | "manifest" | "none";
  firstPlane: string;
  perPlane: string;
  manifest: ManifestDraft | null;
};

export type ManifestDraft = {
  fileName: string;
  header: string[];
  rows: string[][];
  mapping: ColumnMapping;
};

export function emptyDraft(pattern: string): Draft {
  return {
    source: "profile",
    profileId: "",
    count: "1",
    pattern,
    scidStart: "",
    norad: "",
    planeMode: "none",
    firstPlane: "",
    perPlane: "25",
    manifest: null,
  };
}

const { array, integer, nullable, object, oneOf, string } = decoders;
const column = nullable(integer);
const mappingReader: Reader<ColumnMapping> = object({
  name: column,
  scid: column,
  norad: column,
  plane: column,
  slot: column,
  profile: column,
});
const draftReader: Reader<Draft> = (value, path = "") => {
  const raw = object({
    source: oneOf(["profile", "manifest"]),
    profileId: string,
    count: string,
    pattern: string,
    scidStart: string,
    // Drafts saved before NORAD ids existed read as "add later".
    norad: (value: unknown, at?: string) => (value === undefined ? "" : string(value, at)),
    planeMode: oneOf(["fill", "manifest", "none"]),
    firstPlane: string,
    perPlane: string,
    manifest: nullable(
      object({
        fileName: string,
        header: array(string, 64),
        rows: array(array(string, 64), 2000),
        mapping: mappingReader,
      }),
    ),
  })(value, path);
  return {
    ...raw,
    manifest: raw.manifest
      ? {
          ...raw.manifest,
          header: [...raw.manifest.header],
          rows: raw.manifest.rows.map((r) => [...r]),
        }
      : null,
  };
};

const storageKey = (missionId: string) => `apogee.add-spacecraft.${missionId}`;

/** Storage can be unavailable (private mode, quota); the wizard still works without it. */
export function loadDraft(missionId: string): Draft | null {
  try {
    const text = sessionStorage.getItem(storageKey(missionId));
    if (text === null) return null;
    const result = decode(draftReader, JSON.parse(text) as unknown);
    return result.ok ? result.value : null;
  } catch {
    return null;
  }
}

export function saveDraft(missionId: string, draft: Draft): void {
  try {
    sessionStorage.setItem(storageKey(missionId), JSON.stringify(draft));
  } catch {
    // Not persisting is acceptable: the draft stays in memory for this visit.
  }
}

export function clearDraft(missionId: string): void {
  try {
    sessionStorage.removeItem(storageKey(missionId));
  } catch {
    // Nothing to clear.
  }
}

const int = (text: string, min: number, max: number): number | null => {
  const t = text.trim();
  if (!/^\d+$/.test(t)) return null;
  const n = Number(t);
  return n >= min && n <= max ? n : null;
};

export type FieldErrors = Partial<Record<keyof Draft | "manifestRows", string>>;

export type Proposal =
  | Readonly<{ status: "incomplete"; step: "source" | "identity" | "orbit"; errors: FieldErrors }>
  | Readonly<{ status: "ready"; report: ClashReport; profileId: string }>;

/** Validates the draft step by step and builds the proposed batch with clash checks. */
export function propose(
  draft: Draft,
  directory: SpacecraftDirectory,
  profiles: readonly ProfileSummary[],
): Proposal {
  if (!profiles.some((p) => p.id === draft.profileId))
    return {
      status: "incomplete",
      step: "source",
      errors: { profileId: "Pick a profile or a manifest." },
    };

  if (draft.source === "manifest") {
    const m = draft.manifest;
    if (!m)
      return { status: "incomplete", step: "source", errors: { manifest: "Add a manifest." } };
    if (m.mapping.name === null)
      return { status: "incomplete", step: "source", errors: { manifest: "Map the Name column." } };
    // A row may name another profile; it must be one of this mission's profiles.
    const names = new Set(profiles.map((p) => p.name.toLowerCase()));
    const rows = manifestRows(readRows(m.header, m.rows, m.mapping)).map((row) =>
      row.profileName === null || names.has(row.profileName.toLowerCase())
        ? row
        : {
            ...row,
            problems: [...row.problems, `Profile “${row.profileName}” is not in this mission`],
          },
    );
    return {
      status: "ready",
      report: checkClashes(rows, directory.spacecraft, directory.scids?.inUse),
      profileId: draft.profileId,
    };
  }

  const errors: FieldErrors = {};
  const count = int(draft.count, 1, MAX_BATCH);
  if (count === null) errors.count = `Enter a count from 1 to ${MAX_BATCH}.`;
  const pattern = parsePattern(draft.pattern);
  if (!pattern.ok) errors.pattern = pattern.message;
  else if (!pattern.pattern.unique && count !== null && count > 1)
    errors.pattern = "Add {scid} or {n} so each name is different.";
  const start = int(draft.scidStart, 0, MAX_SCID);
  if (start === null) errors.scidStart = `Enter a SCID from 0 to ${MAX_SCID}.`;
  else if (count !== null && start + count - 1 > MAX_SCID)
    errors.scidStart = `The range passes ${MAX_SCID}, the largest SCID.`;
  const norads = count === null ? null : noradList(draft.norad, count);
  if (norads && !norads.ok) errors.norad = norads.message;
  if (
    Object.keys(errors).length > 0 ||
    count === null ||
    start === null ||
    !pattern.ok ||
    !norads?.ok
  )
    return { status: "incomplete", step: "identity", errors };

  let planes = null;
  if (draft.planeMode === "fill") {
    const first = int(draft.firstPlane, 0, 999);
    const per = int(draft.perPlane, 1, 9999);
    if (first === null || per === null)
      return {
        status: "incomplete",
        step: "orbit",
        errors: {
          ...(first === null ? { firstPlane: "Enter a plane number." } : {}),
          ...(per === null ? { perPlane: "Enter how many per plane." } : {}),
        },
      };
    planes = { firstPlane: first, perPlane: per };
  }
  const rows = generateRows(pattern.pattern, count, start, planes, norads.ids);
  return {
    status: "ready",
    report: checkClashes(rows, directory.spacecraft, directory.scids?.inUse),
    profileId: draft.profileId,
  };
}

export const mappableFields = manifestFields;

/** NORAD catalog numbers are positive integers (9 digits leaves room past Alpha-5). */
const MAX_NORAD = 999_999_999;

/**
 * NORAD ids typed for a generated batch: empty = add later (all null); otherwise one per
 * spacecraft, in order, separated by commas or spaces, no repeats.
 */
export function noradList(
  text: string,
  count: number,
): Readonly<{ ok: true; ids: readonly (number | null)[] } | { ok: false; message: string }> {
  const parts = text.split(/[\s,]+/).filter((p) => p !== "");
  if (parts.length === 0) return { ok: true, ids: Array.from({ length: count }, () => null) };
  const ids = parts.map((p) => (/^\d+$/.test(p) ? Number(p) : NaN));
  const bad = parts.find((_, i) => {
    const n = ids[i];
    return n === undefined || !(n >= 1 && n <= MAX_NORAD);
  });
  if (bad !== undefined) return { ok: false, message: `“${bad}” isn't a NORAD id.` };
  if (ids.length !== count)
    return {
      ok: false,
      message: `Enter ${count} NORAD ids, one per spacecraft (you entered ${ids.length}), or leave it empty.`,
    };
  const repeat = ids.find((id, i) => ids.indexOf(id) !== i);
  if (repeat !== undefined) return { ok: false, message: `NORAD id ${repeat} is listed twice.` };
  return { ok: true, ids };
}
