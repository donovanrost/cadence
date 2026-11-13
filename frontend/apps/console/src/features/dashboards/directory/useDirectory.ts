import type { MissionId } from "@/api/index.ts";
import { computed, type Ref } from "vue";
import { useRoute, useRouter, type LocationQueryValue } from "vue-router";
import { useRemoteQuery } from "@/api";
import { useMissionInvalidation } from "@/live";
import { fetchDirectory, sorts, type DirectoryQuery } from "./api.ts";

const one = (v: LocationQueryValue | LocationQueryValue[] | undefined) =>
  typeof v === "string" ? v : "";

/** The directory's filters live in the URL; the listing refetches on `dashboards` invalidations. */
export function useDirectory(missionId: Readonly<Ref<MissionId>>) {
  const route = useRoute();
  const router = useRouter();
  const query = computed<DirectoryQuery>(() => {
    const sort = sorts.find((s) => s === one(route.query.sort)) ?? "updated";
    const page = Number.parseInt(one(route.query.page), 10);
    return {
      q: one(route.query.q),
      tags: one(route.query.tags).split(",").filter(Boolean),
      starred: one(route.query.starred) === "1",
      archived: one(route.query.archived) === "1",
      sort,
      page: Number.isFinite(page) && page > 0 ? page : 1,
    };
  });
  const key = computed(() => JSON.stringify([missionId.value, query.value]));
  const listing = useRemoteQuery(key, (_k, signal) =>
    fetchDirectory(missionId.value, query.value, signal),
  );
  useMissionInvalidation(
    computed(() => missionId.value),
    ["dashboards"],
    listing.refetch,
  );

  /** Changing a filter returns to page 1; null or "" removes the parameter. */
  function set(changes: Record<string, string | null>) {
    const next: Record<string, string> = {};
    for (const [k, v] of Object.entries(route.query)) if (typeof v === "string") next[k] = v;
    if (!("page" in changes)) delete next.page;
    for (const [k, v] of Object.entries(changes)) {
      if (v === null || v === "") delete next[k];
      else next[k] = v;
    }
    void router.replace({ query: next });
  }
  return { query, listing, set };
}
