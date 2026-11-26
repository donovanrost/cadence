import { computed, ref } from "vue";

/**
 * a11y B6 (#276, ux): the person's own act on the plan screens (Draft, Resume, a re-plan's Propose,
 * a day change), so PlanStatePanel can tell a failure they caused from one that just appears. A
 * failure after such an act is an alert; the screen's first load and a background refetch (a
 * dropped connection) are read politely. One flag for the tab: one plan screen is shown at a time.
 */
const acted = ref(false);

/** Call from an act handler: the next failure the panel shows is an alert. */
export function markPlanAct(): void {
  acted.value = true;
}

/** The panel showed something settled (not loading, drafting or failed): forget the act. */
export function settlePlanAct(): void {
  acted.value = false;
}

export const planActRole = computed(() => (acted.value ? ("alert" as const) : ("status" as const)));
