import { computed } from "vue";
import { useRoute, useRouter } from "vue-router";
import type { Span } from "./api.ts";

/** `?day=YYYY-MM-DD&span=day|week|month` (UTC days); defaults today, day. */
export function useReviewWindow() {
  const route = useRoute();
  const router = useRouter();
  const today = () => new Date().toISOString().slice(0, 10);
  const day = computed(() =>
    typeof route.query.day === "string" && /^\d{4}-\d{2}-\d{2}$/.test(route.query.day)
      ? route.query.day
      : today(),
  );
  const span = computed<Span>(() =>
    route.query.span === "week" || route.query.span === "month" ? route.query.span : "day",
  );
  const set = (q: Readonly<{ day?: string; span?: Span }>) =>
    void router.replace({ query: { ...route.query, ...q } }).catch(() => undefined);
  return { day, span, set };
}
