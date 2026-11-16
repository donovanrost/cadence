import { computed, type Ref } from "vue";
import { useRoute, useRouter } from "vue-router";
import { useRemoteQuery, type MissionId, type RemoteState } from "@/api/index.ts";
import { useMissionInvalidation } from "@/live/index.ts";
import type { Pass, Passes } from "../api.ts";
import { isHandStarted } from "../handStarted.ts";
import { fetchWeekLedger, type ShortDay } from "./api.ts";
import {
  apiStates,
  isoDay,
  ledgerRows,
  mondayOf,
  parseHistoryQuery,
  weekSpan,
  type HistoryRow,
} from "./history.ts";

/** A ledger line: a pass, or the text-3 row where a cut day's missing passes belong (U78). */
export type LedgerItem =
  | Readonly<{ kind: "pass"; key: string; pass: HistoryRow }>
  | Readonly<{ kind: "gap"; key: string; day: ShortDay }>;

/**
 * Newest first, each cut day's gap row sits below that day's oldest shown row (the read keeps the
 * newest 500, so its missing passes are older); a cut day with no row shown sits where it would be.
 */
export function ledgerItems(
  rows: readonly HistoryRow[],
  shortDays: readonly ShortDay[],
): LedgerItem[] {
  const items: LedgerItem[] = rows.map((p) => ({ kind: "pass", key: p.id, pass: p }));
  const days = [...shortDays].sort((a, b) => (a.day < b.day ? 1 : -1));
  for (const d of days) {
    const start = Date.parse(`${d.day}T00:00:00Z`);
    const at = items.findIndex((i) => i.kind === "pass" && Date.parse(i.pass.starts_at) < start);
    const gap: LedgerItem = { kind: "gap", key: `gap-${d.day}`, day: d };
    items.splice(at === -1 ? items.length : at, 0, gap);
  }
  return items;
}

/** Contacts › History's URL state, its week read and the rows the ledger shows (A12, U78). */
export function useHistory(missionId: Ref<MissionId>, now: Ref<Date>) {
  const route = useRoute();
  const router = useRouter();
  const query = computed(() => parseHistoryQuery(route.query, now.value.getTime()));
  const span = computed(() => weekSpan(query.value.week, now.value.getTime()));
  const go = (patch: Record<string, string | undefined>) =>
    router
      .replace({ query: { ...route.query, ...patch } })
      .catch((e: unknown) => console.error("Navigation failed", e));

  // Keyed on the week, not on now: the current week reads to next Monday and shows what started.
  const key = computed(() => ({
    m: missionId.value,
    week: query.value.week,
    spacecraftId: query.value.spacecraftId,
    station: query.value.station,
    states: apiStates(query.value.states),
  }));
  const ledger = useRemoteQuery(key, (k, signal) =>
    fetchWeekLedger(k.m, weekSpan(k.week, Date.now()), k, signal),
  );
  useMissionInvalidation(missionId, ["contacts"], ledger.refetch);

  const value = computed(() =>
    ledger.state.value.status === "ready" ? ledger.state.value.value : null,
  );
  const rows = computed(() =>
    ledgerRows(value.value?.passes ?? [], span.value, query.value.states),
  );
  const shortDays = computed(() => value.value?.shortDays ?? []);
  const items = computed(() => ledgerItems(rows.value, shortDays.value));

  /** Opening a row from another week (a Timeline link) moves to the week it started in. */
  function weekOf(p: Readonly<{ starts_at: string }>): string {
    return isoDay(mondayOf(Date.parse(p.starts_at)));
  }

  /**
   * The drawer's read (useSelectedPass) takes booked passes only: a hand-started row isn't in it,
   * so selecting one is read on its own and comes back as `handStarted` (fe-ops 57167b5eb).
   */
  const passes = {
    state: computed((): RemoteState<Passes> => {
      const s = ledger.state.value;
      if (s.status !== "ready") return s;
      const booked: Pass[] = s.value.passes.filter((r): r is Pass => !isHandStarted(r));
      return { ...s, value: { ...s.value, passes: booked } };
    }),
    refetch: ledger.refetch,
  };

  return { query, span, go, ledger, passes, rows, shortDays, items, weekOf };
}
