import type { MissionId } from "@/api/index.ts";
import { PRIORITY_NORMAL } from "../priority.ts";
import {
  DecodeError,
  decoders as d,
  decode,
  request,
  type ApiResult,
  type Decoded,
  type Reader,
} from "@/api/index.ts";
import { fleetStates, type FleetState } from "@/features/fleet/index.ts";
import { catalogRevisionWords, fetchCommand } from "../api.ts";
import type { Release } from "./draft.ts";
import { newItem, type StackItem } from "./stack.ts";
import type { TargetQuery } from "./targets.ts";

/**
 * The operator's saved Compose draft (commanding.md §Compose draft): one per user per mission,
 * inert, autosaved. The document is Compose's editor state, opaque to the server; values stay
 * raw text so invalid input survives a reload (only preflight validates).
 */
const draftPath = (missionId: MissionId) =>
  `/missions/${encodeURIComponent(missionId)}/command-draft`;

const savedReader = d.object({ revision: d.integer, saved_at: d.timestamp });
export type DraftSaved = Decoded<typeof savedReader>;

const opaque: Reader<unknown> = (value) => value;
const storedReader = d.object({
  revision: d.integer,
  saved_at: d.timestamp,
  document: opaque,
  catalog: d.object({
    revision_saved: d.nullable(d.string),
    revision_now: d.nullable(d.string),
    missing_command_ids: d.array(d.token, 500),
  }),
});
export type StoredDraft = Decoded<typeof storedReader>;

/** GET's body: `{draft: <draft> | null}`, with no 404 for "no draft" (qa a11y #6, api 444a187fc). */
export const draftReplyReader = d.object({ draft: d.nullable(storedReader) });

/** The caller's draft, or null when there is none. */
export async function fetchComposeDraft(
  missionId: MissionId,
  signal?: AbortSignal,
): Promise<ApiResult<StoredDraft | null>> {
  const r = await request(draftPath(missionId), draftReplyReader, signal ? { signal } : {});
  return r.ok ? { ok: true, value: r.value.draft } : r;
}

export function saveComposeDraft(
  missionId: MissionId,
  document: ComposeDocument,
  expectedRevision: number | null,
) {
  return request(draftPath(missionId), savedReader, {
    method: "PUT",
    body: { document, expected_revision: expectedRevision },
  });
}

export function discardComposeDraft(missionId: MissionId) {
  return request(draftPath(missionId), () => null, { method: "DELETE" });
}

/**
 * 409 command_draft_changed: the revision another tab or device saved. Null when the draft is gone
 * (details `{revision: null, saved_at: null}`: submitted or discarded elsewhere, api).
 */
export function changedBy(details: unknown): DraftSaved | null {
  const r = decode(savedReader, details);
  return r.ok ? r.value : null;
}

const text = (v: unknown, path = ""): Readonly<Record<string, string>> => {
  if (typeof v !== "object" || v === null || Array.isArray(v))
    throw new DecodeError(path, "object");
  const out: Record<string, string> = {};
  for (const [k, value] of Object.entries(v)) out[k] = d.string(value, `${path}.${k}`);
  return out;
};
/** argument id → spacecraft id → raw text (B2); older documents have `{}` or nothing. */
const perTargetText = (
  v: unknown,
  path = "",
): Readonly<Record<string, Readonly<Record<string, string>>>> => {
  if (typeof v !== "object" || v === null || Array.isArray(v))
    throw new DecodeError(path, "object");
  const out: Record<string, Readonly<Record<string, string>>> = {};
  for (const [k, value] of Object.entries(v)) out[k] = text(value, `${path}.${k}`);
  return out;
};
const isFleetState = (s: string): s is FleetState => (fleetStates as readonly string[]).includes(s);

const documentReader = d.object({
  schema_version: d.literal(1),
  title: d.string,
  log_entry: d.string,
  target_query: d.object({
    plane: d.nullable(d.integer),
    profile: d.nullable(d.token),
    states: d.array(d.token, 10),
    explicit: d.array(d.token, 1_000),
  }),
  endpoints: text,
  stack: d.array(
    d.object({
      command_id: d.token,
      values: text,
      per_target: d.optional((v, path = "") => perTargetText(v, path)),
    }),
    500,
  ),
  release: d.object({
    mode: d.oneOf(["next_contact", "not_before"] as const),
    not_before: d.nullable(d.timestamp),
    /** U68: absent on drafts saved before expiry and priority existed. */
    expires_at: d.optional(d.nullable(d.timestamp)),
    priority: d.optional(d.integer),
  }),
  requested_approver_user_id: d.nullable(d.token),
  sent_back_from: d.nullable(d.token),
});

export type ComposeFields = Readonly<{
  title: string;
  log: string;
  query: TargetQuery;
  endpoints: Readonly<Record<string, string>>;
  stack: readonly StackItem[];
  release: Release;
  approver: string;
  sentBackFrom: string | null;
}>;

export type ComposeDocument = ReturnType<typeof toDocument>;

/** Compose's state as the server stores it (schema_version 1). */
export function toDocument(f: ComposeFields) {
  return {
    schema_version: 1 as const,
    title: f.title,
    log_entry: f.log,
    origin: f.sentBackFrom === null ? null : { kind: "sent_back" as const, id: f.sentBackFrom },
    target_query: {
      plane: f.query.plane,
      profile: f.query.profile,
      states: [...f.query.states],
      explicit: [...f.query.explicit],
    },
    endpoints: { ...f.endpoints },
    stack: f.stack.map((i) => ({
      key: i.key,
      command_id: i.command.id,
      values: { ...i.values },
      per_target: Object.fromEntries(
        Object.entries(i.perTarget).map(([arg, byTarget]) => [arg, { ...byTarget }]),
      ),
    })),
    release: {
      mode: f.release.mode,
      not_before:
        f.release.mode === "not_before" && f.release.notBefore !== null
          ? new Date(f.release.notBefore).toISOString()
          : null,
      expires_at: f.release.expiresAt === null ? null : new Date(f.release.expiresAt).toISOString(),
      priority: f.release.priority,
    },
    requested_approver_user_id: f.approver || null,
    sent_back_from: f.sentBackFrom,
  };
}

/** Nothing worth keeping: no targets, commands, title or log. */
export const isBlank = (f: ComposeFields) =>
  f.stack.length === 0 &&
  f.query.explicit.length === 0 &&
  f.query.plane === null &&
  f.query.profile === null &&
  f.query.states.length === 0 &&
  !f.title.trim() &&
  !f.log.trim();

export type Restored = Readonly<{
  fields: ComposeFields;
  /** The catalog revision the stack was read from, for C2's line. */
  revisionId: string | null;
  catalogRev: string | null;
  /** Stacked commands the active catalog no longer has (left out). */
  gone: number;
}>;

/**
 * A saved document back into Compose's state. Commands are re-read from the active catalog;
 * saved text is kept per argument that still exists, even when invalid (C2 flags it).
 */
export async function restoreDraft(
  missionId: MissionId,
  stored: StoredDraft,
): Promise<{ ok: true; value: Restored } | { ok: false; message: string }> {
  const doc = decode(documentReader, stored.document);
  if (!doc.ok) return { ok: false, message: "This draft was saved in a form Compose can't read." };
  const v = doc.value;
  const missing = new Set(stored.catalog.missing_command_ids);
  const stack: StackItem[] = [];
  let gone = 0;
  let revisionId: string | null = null;
  let catalogRev: string | null = null;
  for (const s of v.stack) {
    const r = missing.has(s.command_id) ? null : await fetchCommand(missionId, s.command_id);
    if (r && !r.ok) return { ok: false, message: "Couldn't read the draft's commands." };
    const detail = r?.value.command;
    if (!r || !detail) {
      gone += 1;
      continue;
    }
    revisionId = r.value.revision_id;
    catalogRev = catalogRevisionWords(r.value.catalog_revision);
    const item = newItem(detail);
    const values = { ...item.values };
    for (const arg of detail.arguments) {
      const saved = s.values[arg.id];
      if (saved !== undefined) values[arg.id] = saved;
    }
    // Per target only for arguments the command still has.
    const known = new Set(detail.arguments.map((a) => a.id));
    const perTarget = Object.fromEntries(
      Object.entries(s.per_target ?? {}).filter(([arg]) => known.has(arg)),
    );
    stack.push({ ...item, values, perTarget });
  }
  const nb = v.release.not_before;
  return {
    ok: true,
    value: {
      fields: {
        title: v.title,
        log: v.log_entry,
        query: { ...v.target_query, states: v.target_query.states.filter(isFleetState) },
        endpoints: v.endpoints,
        stack,
        release: {
          ...(v.release.mode === "not_before"
            ? { mode: "not_before" as const, notBefore: nb ? Date.parse(nb) : null }
            : { mode: "next_contact" as const, notBefore: null }),
          expiresAt: v.release.expires_at ? Date.parse(v.release.expires_at) : null,
          priority: v.release.priority ?? PRIORITY_NORMAL,
        },
        approver: v.requested_approver_user_id ?? "",
        sentBackFrom: v.sent_back_from,
      },
      revisionId,
      catalogRev,
      gone,
    },
  };
}
