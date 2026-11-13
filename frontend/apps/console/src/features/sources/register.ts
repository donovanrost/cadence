import type { ApSelectOption } from "@/ui";
import type { RegisterBody, SourceOptions } from "./writes.ts";

/** The Register sheet's draft (L11 W1). */
export type RegisterDraft = Readonly<{
  name: string;
  logical: string;
  kind: "" | "byo_tsdb" | "managed_tsdb";
  isolation: string;
  storage: string;
  credentials: string;
}>;
export const blankDraft: RegisterDraft = {
  name: "",
  logical: "",
  kind: "",
  isolation: "",
  storage: "",
  credentials: "",
};

const known = <K extends string>(k: K | "unrecognized"): k is K => k !== "unrecognized";

/** R1's choices as select options; a key this console doesn't know is left out. */
export function choices(o: SourceOptions, kind: RegisterDraft["kind"]) {
  return {
    logical: o.logical_sources.map((l) => ({ value: l.key, label: l.label })),
    kinds: o.kinds.flatMap((k): ApSelectOption<"byo_tsdb" | "managed_tsdb">[] =>
      known(k.key) ? [{ value: k.key, label: k.label }] : [],
    ),
    isolation:
      kind === ""
        ? []
        : o.isolation_levels[kind].flatMap((i): ApSelectOption<string>[] =>
            known(i.key) ? [{ value: i.key, label: i.label }] : [],
          ),
    storages: o.storages.flatMap((s): ApSelectOption<string>[] =>
      known(s.key) ? [{ value: s.key, label: s.label }] : [],
    ),
  };
}

/** R1 says per kind whether it needs a credentials reference. */
export const needsCredentials = (o: SourceOptions | null, kind: RegisterDraft["kind"]) =>
  o?.kinds.find((k) => k.key === kind)?.requires_credentials ?? false;

export function blockedReason(d: RegisterDraft, o: SourceOptions | null, busy: boolean) {
  if (!d.name.trim() || !d.logical || !d.kind || !d.isolation || !d.storage)
    return "Fill in every field.";
  if (needsCredentials(o, d.kind) && !d.credentials.trim())
    return "This kind needs a credentials reference.";
  return busy ? "Registering…" : null;
}

/** The W1 body, or null while the draft isn't complete. */
export function registerBody(d: RegisterDraft, o: SourceOptions | null): RegisterBody | null {
  if (d.kind === "" || blockedReason(d, o, false) !== null) return null;
  return {
    display_name: d.name.trim(),
    logical_source: d.logical,
    kind: d.kind,
    isolation_level: d.isolation,
    storage: d.storage,
    ...(needsCredentials(o, d.kind) ? { credentials_ref: d.credentials.trim() } : {}),
  };
}
