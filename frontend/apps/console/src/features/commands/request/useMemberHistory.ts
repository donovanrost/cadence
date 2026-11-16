import type { MissionId } from "@/api/index.ts";
import { describeApiError } from "@/api/index.ts";
import { shallowRef } from "vue";
import { fetchHistory, type Attempt, type HistoryVerifier } from "./history.ts";

type Loaded = Readonly<{
  /** Oldest first, as ux tells the story (the server pages attempts newest first). */
  attempts: readonly Attempt[];
  attemptsNext: string | null;
  verifiers: readonly HistoryVerifier[];
  verifiersNext: string | null;
}>;
export type MemberHistoryState =
  | Readonly<{ status: "loading" }>
  | Readonly<{ status: "failed"; error: string }>
  | Readonly<{ status: "ready"; value: Loaded; more: boolean }>;

/**
 * One member's history (U68 R3/R4): the first page on load, then earlier attempts or later
 * verifiers on request. A failed page keeps what's shown and says so.
 */
export function useMemberHistory(missionId: () => MissionId, requestId: () => string) {
  const state = shallowRef<MemberHistoryState>({ status: "loading" });
  const pageError = shallowRef<string | null>(null);

  async function load() {
    state.value = { status: "loading" };
    const r = await fetchHistory(missionId(), requestId());
    state.value = r.ok
      ? {
          status: "ready",
          more: false,
          value: {
            attempts: [...r.value.attempts].reverse(),
            attemptsNext: r.value.attempts_next,
            verifiers: r.value.verifiers,
            verifiersNext: r.value.verifiers_next,
          },
        }
      : { status: "failed", error: describeApiError(r.error) };
  }

  async function page(which: "attempts" | "verifiers") {
    const s = state.value;
    if (s.status !== "ready" || s.more) return;
    const cursor = which === "attempts" ? s.value.attemptsNext : s.value.verifiersNext;
    if (!cursor) return;
    state.value = { ...s, more: true };
    pageError.value = null;
    const r = await fetchHistory(missionId(), requestId(), { [which]: cursor });
    if (!r.ok) {
      pageError.value = `Couldn't load more: ${describeApiError(r.error)}`;
      state.value = { ...s, more: false };
      return;
    }
    state.value = {
      status: "ready",
      more: false,
      value:
        which === "attempts"
          ? {
              ...s.value,
              attempts: [...[...r.value.attempts].reverse(), ...s.value.attempts],
              attemptsNext: r.value.attempts_next,
            }
          : {
              ...s.value,
              verifiers: [...s.value.verifiers, ...r.value.verifiers],
              verifiersNext: r.value.verifiers_next,
            },
    };
  }

  return {
    state,
    pageError,
    load: () => load().catch((e: unknown) => console.error("History failed", e)),
    earlier: () => page("attempts").catch((e: unknown) => console.error("History failed", e)),
    later: () => page("verifiers").catch((e: unknown) => console.error("History failed", e)),
  };
}
