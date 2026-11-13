import type { HostActionReceipt } from "@cadence/plugin-sdk";

/**
 * L9 save-outcome seam (DECISIONS #77, lead): the host never hard-wires "saved now". Each app's
 * adapter turns an action receipt into what the frame says. Today (A) apps save on their own terms
 * and telemetry_decom's activation goes to approvals (L10); if app config later goes through change
 * sets (B), an adapter returns `staged` and the frame shows the staged bar instead. Never claim
 * `staged` where nothing is staged.
 */
export type SaveOutcome =
  | Readonly<{ kind: "saved"; text: string }>
  | Readonly<{ kind: "activation_requested"; text: string }>
  | Readonly<{ kind: "staged"; count: number }>;

export type SaveAdapter = (actionId: string, receipt: HostActionReceipt) => SaveOutcome | null;

/** Saves the app reports as done: definitions are versioned by the app itself (limits, derived). */
const savesNow: SaveAdapter = (actionId) =>
  actionId.startsWith("save") ? { kind: "saved", text: "Saved. It applies now." } : null;

const adapters: Readonly<Record<string, SaveAdapter>> = {
  limits: savesNow,
  derived_telemetry: savesNow,
  telemetry_decom: (actionId, receipt) =>
    actionId === "request_activation"
      ? {
          kind: "activation_requested",
          text: "Activation requested. It applies once it's approved.",
        }
      : savesNow(actionId, receipt),
};

/** Unknown apps say nothing rather than guess (U20); the app's own UI shows its result. */
export function saveOutcome(
  appKey: string,
  actionId: string,
  receipt: HostActionReceipt,
): SaveOutcome | null {
  return adapters[appKey]?.(actionId, receipt) ?? null;
}

/**
 * How an app's saves take effect, for the frame's tag (ux AppSurfaces #77): `immediate` shows
 * `SAVES IMMEDIATELY`; `activation` waits for an approval (L10). Unknown apps show nothing.
 */
export type SaveMode = "immediate" | "activation";
const modes: Readonly<Record<string, SaveMode>> = {
  limits: "immediate",
  derived_telemetry: "immediate",
  telemetry_decom: "activation",
};
export const saveMode = (appKey: string): SaveMode | null => modes[appKey] ?? null;
