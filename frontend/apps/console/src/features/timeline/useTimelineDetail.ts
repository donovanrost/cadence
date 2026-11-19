import type { MissionId } from "@/api/index.ts";
import { nextTick, onBeforeUnmount, ref, watch, type Ref } from "vue";
import type { WindowSel } from "@/features/telemetry/index.ts";
import type { Events, MissionEvent } from "./api.ts";
import { useEventSelection } from "./useEventSelection.ts";

/**
 * The Timeline's event detail (ux decisions U71 A8): a row's time selects it (?event=<id>). From
 * 1100 the detail is an aside beside the log; below, a sheet. A permalink centres the window on the
 * event, keeping its span and ending no later than now, and focuses the panel's title.
 */
export function useTimelineDetail(
  options: Readonly<{
    /** The screen's template refs: the detail (to focus its title) and the sheet below 1100. */
    detail: Readonly<Ref<{ focusTitle: () => void } | null>>;
    detailSheet: Readonly<Ref<{ open: () => void; close: () => void } | null>>;
    missionId: Readonly<Ref<MissionId>>;
    shown: Readonly<Ref<readonly MissionEvent[] | null>>;
    page: Readonly<Ref<Pick<Events, "from" | "to"> | null>>;
    setWindow: (next: WindowSel) => void;
  }>,
) {
  const listWindow = ref<{ from: number; to: number } | null>(null);
  watch(
    options.page,
    (p) => {
      listWindow.value = p ? { from: Date.parse(p.from), to: Date.parse(p.to) } : null;
    },
    { immediate: true },
  );
  function centreOn(at: number) {
    const w = listWindow.value;
    const span = w ? w.to - w.from : 86_400_000;
    const to = Math.min(at + span / 2, Date.now());
    options.setWindow({ kind: "custom", from: to - span, to });
  }
  const selection = useEventSelection({
    missionId: options.missionId,
    shown: options.shown,
    window: listWindow,
    centreOn,
  });
  const query =
    typeof window.matchMedia === "function" ? window.matchMedia("(min-width: 68.75rem)") : null;
  const wide = ref(query?.matches ?? true);
  const onWide = (e: MediaQueryListEvent) => (wide.value = e.matches);
  query?.addEventListener("change", onWide);
  onBeforeUnmount(() => query?.removeEventListener("change", onWide));
  const { detail, detailSheet } = options;
  let fromLink = selection.selectedId.value !== null;
  watch(selection.event, async (e) => {
    if (!e) {
      detailSheet.value?.close();
      return;
    }
    if (!wide.value) detailSheet.value?.open();
    if (!fromLink) return;
    fromLink = false;
    await nextTick();
    detail.value?.focusTitle();
  });
  return { selection, wide };
}
