import { onBeforeUnmount, onMounted, reactive, ref } from "vue";
import type {
  ContactSchedule,
  ScheduleOpportunity,
  ScheduleRoute,
  ScheduleSearch,
  ScheduleSearchResult,
} from "./OpsContactSchedule.contracts";
import { parseScheduleUTC } from "./contact-schedule";

export const invalidScheduleWindow = "Choose a future UTC window of at most seven days.";
export function createScheduleDraft(schedule: ContactSchedule | null | undefined) {
  return {
    route_key: schedule?.routes.entries[0]?.key ?? "",
    starts_at: schedule?.initial_window.starts_at.slice(0, 19) ?? "",
    ends_at: schedule?.initial_window.ends_at.slice(0, 19) ?? "",
  };
}
export function scheduleSearch(
  draft: ReturnType<typeof createScheduleDraft>,
  route: ScheduleRoute,
  now = Date.now(),
): ScheduleSearch | null {
  const starts = parseScheduleUTC(draft.starts_at),
    ends = parseScheduleUTC(draft.ends_at);
  if (
    !Number.isFinite(starts) ||
    !Number.isFinite(ends) ||
    ends <= starts ||
    starts < now - 60000 ||
    ends - starts > 604800000
  )
    return null;
  return {
    spacecraft_id: route.spacecraft_id,
    route_key: route.key,
    starts_at: new Date(starts).toISOString().replace(".000Z", "Z"),
    ends_at: new Date(ends).toISOString().replace(".000Z", "Z"),
  };
}
export function availableOpportunity(
  result: ScheduleSearchResult | null,
  opportunity: ScheduleOpportunity,
  now: number,
): boolean {
  return (
    ["available", "limited"].includes(opportunity.availability) &&
    Date.parse(opportunity.expires_at) > now &&
    !!result?.opportunities.includes(opportunity)
  );
}

/** Draft ownership and expiry-clock cleanup are identical for both transport protocols. */
export function useScheduleDraft(schedule: () => ContactSchedule | null | undefined) {
  const draft = reactive(createScheduleDraft(schedule()));
  const now = ref(Date.now());
  let ticker: ReturnType<typeof setInterval> | undefined;
  onMounted(() => {
    ticker = setInterval(() => {
      now.value = Date.now();
    }, 1000);
  });
  onBeforeUnmount(() => clearInterval(ticker));
  return { draft, now };
}
