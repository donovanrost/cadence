import type { ScopeDefault, TimeDefault } from "./api.ts";

/** General › defaults as form text (ux: range and spacecraft the dashboard opens with). */
export type DefaultsForm = {
  time: string; // a preset like "now-6h", "absolute", or "" (none)
  from: string;
  to: string;
  scope: "context" | "fixed" | "fleet" | "";
  spacecraftId: string;
};

export const rangePresets = [
  { value: "now-1h", label: "Last hour" },
  { value: "now-6h", label: "Last 6 hours" },
  { value: "now-24h", label: "Last 24 hours" },
  { value: "now-7d", label: "Last 7 days" },
] as const;

export function toForm(time: TimeDefault, scope: ScopeDefault): DefaultsForm {
  return {
    time: time === null ? "" : time.mode === "absolute" ? "absolute" : (time.range ?? ""),
    from: time?.from ?? "",
    to: time?.to ?? "",
    scope: scope?.mode ?? "",
    spacecraftId: scope?.spacecraft_id ?? "",
  };
}

/** Back to the wire, or the field that's wrong. */
export function fromForm(
  f: DefaultsForm,
): Readonly<
  | { ok: true; time: TimeDefault; scope: ScopeDefault }
  | { ok: false; field: "from" | "to" | "spacecraftId"; message: string }
> {
  let time: TimeDefault = null;
  if (f.time === "absolute") {
    const from = Date.parse(f.from);
    const to = Date.parse(f.to);
    if (Number.isNaN(from))
      return { ok: false, field: "from", message: "Enter a UTC time like 2026-11-12T21:00Z." };
    if (Number.isNaN(to) || to <= from)
      return { ok: false, field: "to", message: "Enter a UTC time after the start." };
    time = {
      mode: "absolute",
      range: null,
      from: new Date(from).toISOString(),
      to: new Date(to).toISOString(),
    };
  } else if (f.time !== "") time = { mode: "relative", range: f.time, from: null, to: null };
  if (f.scope === "fixed" && f.spacecraftId === "")
    return { ok: false, field: "spacecraftId", message: "Choose the spacecraft." };
  const scope: ScopeDefault =
    f.scope === ""
      ? null
      : { mode: f.scope, spacecraft_id: f.scope === "fixed" ? f.spacecraftId : null };
  return { ok: true, time, scope };
}
