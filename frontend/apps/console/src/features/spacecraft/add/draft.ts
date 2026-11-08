import { decode, decoders, type Reader } from "@/api";
import type { SpacecraftDirectory } from "../api.ts";
import { checkClashes, generateRows, manifestRows, MAX_BATCH, type ClashReport } from "./batch.ts";
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
export function propose(draft: Draft, directory: SpacecraftDirectory): Proposal {
  const profiles = new Set(directory.spacecraft.flatMap((r) => (r.profile ? [r.profile.id] : [])));
  if (!profiles.has(draft.profileId))
    return { status: "incomplete", step: "source", errors: { profileId: "Choose a profile." } };

  if (draft.source === "manifest") {
    const m = draft.manifest;
    if (!m)
      return { status: "incomplete", step: "source", errors: { manifest: "Add a manifest." } };
    if (m.mapping.name === null)
      return { status: "incomplete", step: "source", errors: { manifest: "Map the Name column." } };
    const rows = manifestRows(readRows(m.header, m.rows, m.mapping));
    return {
      status: "ready",
      report: checkClashes(rows, directory.spacecraft),
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
  const start = int(draft.scidStart, 0, 65535);
  if (start === null) errors.scidStart = "Enter a SCID from 0 to 65535.";
  else if (count !== null && start + count - 1 > 65535)
    errors.scidStart = "The range passes 65535.";
  if (Object.keys(errors).length > 0 || count === null || start === null || !pattern.ok)
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
  const rows = generateRows(pattern.pattern, count, start, planes);
  return {
    status: "ready",
    report: checkClashes(rows, directory.spacecraft),
    profileId: draft.profileId,
  };
}

export const mappableFields = manifestFields;

export type ProfileChoice = Readonly<{ id: string; name: string; version: number; count: number }>;

/**
 * Profiles in use by the mission, from the directory, until the profiles endpoint lands
 * (setup-shapes.md §P). A profile no spacecraft uses yet can't be picked here.
 */
export function profileChoices(directory: SpacecraftDirectory): readonly ProfileChoice[] {
  const byId = new Map<string, ProfileChoice>();
  for (const row of directory.spacecraft) {
    const p = row.profile;
    if (!p) continue;
    const seen = byId.get(p.id);
    byId.set(p.id, {
      id: p.id,
      name: p.name ?? "Deleted profile",
      version: Math.max(seen?.version ?? 0, p.version),
      count: (seen?.count ?? 0) + 1,
    });
  }
  return [...byId.values()].sort((a, b) => a.name.localeCompare(b.name));
}
