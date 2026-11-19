import { computed, ref, watch } from "vue";
import type { RemoteState } from "@/api";
import { plural } from "@/ui";
import type { Preview } from "./actions.ts";
import { checkKeyText } from "./preview.ts";

/**
 * K2 while the checks re-run (ux B4 ruling, screens/Changes.md K2). Another user's staging moves the
 * set's version and the checks run again; the previous rows stay, dimmed, named in words, until the
 * new ones replace them. The first load still reads "Running checks…".
 */

/** The last checks that ran, and how many changes the set had when they did. */
export type HeldChecks = Readonly<{ preview: Preview; count: number }>;

export const heldLabel = (held: HeldChecks) =>
  `From the previous check (${plural(held.count, "change")})`;
export const checkingLine = (now: number) =>
  `Checking again: the change set now has ${plural(now, "change")}.`;
export const RECHECK_FAILED = "The checks couldn't run for the new changes.";
/** Apply's reasons while the checks shown aren't the current set's. */
export const RECHECKING_REASON = "Checks are re-running for the new changes.";
export const NOT_RUN_REASON = "Checks haven't run for the current changes.";

/** The status line once new results replace the old: "Checks done: 1 NO-GO, 2 holds." */
export function doneLine(preview: Preview): string {
  const noGo = preview.checks.filter((c) => c.verdict === "no_go").length;
  const holds = preview.checks.filter((c) => c.verdict === "hold").length;
  if (noGo === 0 && holds === 0) return "Checks done: all GO.";
  const parts = [
    ...(noGo > 0 ? [`${noGo} NO-GO`] : []),
    ...(holds > 0 ? [plural(holds, "hold")] : []),
  ];
  return `Checks done: ${parts.join(", ")}.`;
}

/** What the HOLD checks hold, so the acknowledgement clears only when the holds changed (ux). */
export function holdsKey(preview: Preview): string {
  return JSON.stringify(
    preview.checks
      .filter((c) => c.verdict === "hold")
      .map((c) => [
        checkKeyText(c.key),
        c.items.map((i) => [i.op_id ?? null, i.entity_id ?? null, i.reason ?? null]),
      ]),
  );
}

/**
 * Keeps the last ready checks for the open set (reset when the set changes) and whether new results
 * have just replaced re-running ones, for the status line.
 */
export function useHeldChecks(
  state: () => RemoteState<Preview>,
  count: () => number | null,
  setId: () => string | null,
) {
  const last = ref<HeldChecks | null>(null);
  const rechecked = ref(false);
  watch(setId, () => {
    last.value = null;
    rechecked.value = false;
  });
  // "Checks done" only after the checks were actually away (re-running or failed) with rows held;
  // a plain refetch keeps the value, never leaves "ready", and so announces nothing (ux review).
  let away = false;
  watch(
    state,
    (s) => {
      if (s.status !== "ready") {
        away = last.value !== null;
        return;
      }
      rechecked.value = away;
      away = false;
      last.value = { preview: s.value, count: count() ?? 0 };
    },
    { immediate: true },
  );
  /** Held rows only while the current checks aren't ready. */
  const held = computed(() => (state().status === "ready" ? null : last.value));
  /** "Checks done: …" once results arrive after a re-run; null on a first load. */
  const done = computed(() => {
    const s = state();
    return s.status === "ready" && rechecked.value ? doneLine(s.value) : null;
  });
  return { held, done };
}
