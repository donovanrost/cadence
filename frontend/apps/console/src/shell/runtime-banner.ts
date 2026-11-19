import { onScopeDispose, ref, watch, type Ref } from "vue";
import { formatHourMinute } from "@/ui";
import type { RuntimeStatus } from "./counts.ts";

/** What the U38 strip shows: the outage, the 5 s "resumed" line, or nothing. */
export type RuntimeBanner =
  | Readonly<{ tone: "crit"; text: string }>
  | Readonly<{ tone: "nominal"; text: string }>
  | null;

const at = (iso: string) => formatHourMinute(new Date(iso));

/**
 * U38 (ux): "Telemetry isn't being processed for EARENDIL since 23:12Z. The runtime hasn't applied
 * the configuration activated at 23:10Z." Each time only when the server sends it (U20): `since`
 * is when applying first failed, `activated_at` when the configuration was activated.
 */
export function outageText(runtime: RuntimeStatus, mission: string): string {
  const since = runtime.since ? ` since ${at(runtime.since)}` : "";
  const what = runtime.activated_at
    ? `configuration activated at ${at(runtime.activated_at)}`
    : "active configuration";
  // Retrying can't clear these: a fault in Cadence (domain, ux U91), not the mission's to fix.
  const fix = NEEDS_FIX.has(runtime.reason ?? "") ? " It needs a fix in Cadence." : "";
  return `Telemetry isn't being processed for ${mission}${since}. The runtime hasn't applied the ${what}.${fix}`;
}

const NEEDS_FIX: ReadonlySet<string> = new Set(["spec_mismatch", "reconcile_crashed"]);

/** "Telemetry processing resumed at 23:26Z." Null without the server's applied_at (U20). */
export function resumedText(runtime: RuntimeStatus | null | undefined): string | null {
  return runtime?.state === "applied" && runtime.applied_at
    ? `Telemetry processing resumed at ${at(runtime.applied_at)}.`
    : null;
}

export const RESUMED_MS = 5_000;

/**
 * The strip for the shell: crit while the runtime is `not_applied`; after this page saw it
 * recover, nominal for 5 s, then gone. A page opened after recovery shows nothing. It can't be
 * dismissed. An unknown state reads as nothing to say. `runtime` is undefined while there's no
 * counts read, and null when the server has nothing to say.
 */
export function useRuntimeBanner(
  runtime: Readonly<Ref<RuntimeStatus | null | undefined>>,
  mission: Readonly<Ref<string | null>>,
): Readonly<Ref<RuntimeBanner>> {
  const banner = ref<RuntimeBanner>(null);
  let timer: ReturnType<typeof setTimeout> | null = null;
  const clear = () => {
    if (timer !== null) clearTimeout(timer);
    timer = null;
  };
  let wasDown = false;
  watch(
    [runtime, mission],
    ([r, name], [, previousName]) => {
      if (name !== previousName) {
        // Another mission: its own history.
        wasDown = false;
        clear();
        banner.value = null;
      }
      // No read (counts failed or still loading): keep what's shown. A failing read during an
      // outage must not hide it.
      if (!name || r === undefined) return;
      if (r?.state === "not_applied") {
        clear();
        wasDown = true;
        banner.value = { tone: "crit", text: outageText(r, name) };
        return;
      }
      const resumed = wasDown ? resumedText(r) : null;
      wasDown = false;
      if (resumed) {
        clear();
        banner.value = { tone: "nominal", text: resumed };
        timer = setTimeout(() => {
          timer = null;
          banner.value = null;
        }, RESUMED_MS);
      } else if (timer === null) banner.value = null;
    },
    { immediate: true },
  );
  onScopeDispose(clear);
  return banner;
}
