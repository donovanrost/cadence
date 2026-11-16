import { computed } from "vue";
import { useRoute, useRouter } from "vue-router";
import { filtersOf, withFilter } from "./filters.ts";

/** ux U69 A6: the filter row's state, in the URL (?sc=, ?severity=). */
export function useAlarmFilters() {
  const route = useRoute();
  const router = useRouter();
  const go = (query: typeof route.query) =>
    router.replace({ query }).catch((e: unknown) => console.error("Navigation failed", e));
  return {
    filters: computed(() => filtersOf(route.query)),
    setFilter: (key: "sc" | "severity", value: string | null) =>
      go(withFilter(route.query, key, value)),
    clearFilters: () => {
      const { sc: _sc, severity: _sev, ...rest } = route.query;
      return go(rest);
    },
  };
}
