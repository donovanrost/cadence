import { computed, onBeforeUnmount, ref, shallowRef, watch, type Ref } from "vue";
import type { OpsPagePort, OpsPageContext } from "@cadence/plugin-sdk/ops-pages";
import { queryKeys, type Catalog, type Query } from "../../shared/command-draft/contracts";
import { readCatalogPage } from "./contracts";

export type CatalogResults<T> = Readonly<{
  query: string;
  entries: readonly T[];
  loading: boolean;
  error: string;
  hasMore: boolean;
  scrollKey: number;
}>;
type Request = { after: string; generation: number };
type LoadState = { status: "idle" } | { status: "loading" } | { status: "failed"; after: string };

export function useCatalogResults<T extends { id: string }>(options: {
  catalog: Readonly<Ref<Catalog | null>>;
  blocked: Readonly<Ref<boolean>>;
  port: OpsPagePort;
  context: OpsPageContext;
  actor: string;
  queryKey: "target_query" | "command_query";
  afterKey: "target_after" | "command_after";
  pick: (catalog: Catalog) => { entries: readonly T[]; next_after: string | null };
  onSpacecraft: (rows: readonly { id: string; name: string }[]) => void;
  onStale: () => Promise<void>;
}) {
  const query = ref(options.catalog.value?.query[options.queryKey] ?? "");
  const entries = shallowRef<readonly T[]>([]);
  const nextAfter = ref<string | null>(null);
  const phase = shallowRef<LoadState>({ status: "idle" });
  const scrollKey = ref(0);
  let generation = 0;
  let disposed = false;
  let timer: ReturnType<typeof setTimeout> | undefined;
  let pending: Request | undefined;
  // Endpoint discovery is mission-wide; selecting a spacecraft only changes the command catalog.
  const identity = (catalog: Catalog | null) =>
    catalog
      ? options.queryKey === "target_query"
        ? "mission-targets"
        : `${catalog.basis.token}:${catalog.query.target}`
      : "";

  function cancel() {
    generation++;
    clearTimeout(timer);
    pending = undefined;
    phase.value = { status: "idle" };
  }
  function schedule(after: string, delay = 0) {
    phase.value = { status: "loading" };
    const request = { after, generation };
    if (delay)
      timer = setTimeout(() => {
        pending = request;
        void drain();
      }, delay);
    else {
      pending = request;
      void drain();
    }
  }
  async function drain() {
    if (disposed || options.blocked.value || !pending || !options.catalog.value) return;
    const request = pending;
    pending = undefined;
    const basis = identity(options.catalog.value);
    const requested: Query = {
      ...options.catalog.value.query,
      [options.queryKey]: query.value,
      [options.afterKey]: request.after,
    };
    const current = () => !disposed && request.generation === generation;
    try {
      const raw = await options.port.execute("catalog_page", { query: requested });
      if (!current()) return;
      const result = readCatalogPage(raw, options.context, options.actor);
      if (!queryKeys.every((key) => result.catalog.query[key] === requested[key]))
        throw Error("Changed catalog query");
      if (identity(result.catalog) !== basis) {
        await options.onStale();
        throw Error("Changed catalog basis");
      }
      if (!current()) return;
      const page = options.pick(result.catalog);
      entries.value = request.after
        ? [
            ...new Map(
              [...entries.value, ...page.entries].map((entry) => [entry.id, entry]),
            ).values(),
          ]
        : page.entries;
      nextAfter.value = page.next_after;
      options.onSpacecraft(result.spacecraft);
      phase.value = { status: "idle" };
    } catch {
      if (current()) phase.value = { status: "failed", after: request.after };
    }
  }
  function search(value: string) {
    if (disposed || value === query.value) return;
    cancel();
    query.value = value;
    nextAfter.value = null;
    scrollKey.value++;
    if (options.catalog.value) schedule("", 200);
  }
  function loadMore() {
    if (phase.value.status === "idle" && nextAfter.value && !options.blocked.value)
      schedule(nextAfter.value);
  }
  function retry() {
    if (phase.value.status === "failed") schedule(phase.value.after);
  }
  watch(options.blocked, () => {
    void drain();
  });
  watch(
    options.catalog,
    (catalog, previous) => {
      const changed = identity(catalog) !== identity(previous ?? null);
      if (changed || !previous) {
        cancel();
        entries.value = [];
        nextAfter.value = null;
        scrollKey.value++;
        if (!catalog) return;
        if (catalog.query[options.queryKey] !== query.value || catalog.query[options.afterKey]) {
          schedule("");
          return;
        }
        const page = options.pick(catalog);
        entries.value = page.entries;
        nextAfter.value = page.next_after;
      } else if (
        catalog &&
        phase.value.status === "idle" &&
        catalog.query[options.queryKey] === query.value &&
        !catalog.query[options.afterKey]
      ) {
        const page = options.pick(catalog);
        // Live snapshots refresh the first page without discarding later pages or the search.
        if (!page.next_after || entries.value.length <= page.entries.length) {
          entries.value = page.entries;
          nextAfter.value = page.next_after;
        } else {
          const boundary = page.next_after;
          entries.value = [
            ...page.entries,
            ...entries.value.filter((entry) => entry.id > boundary),
          ];
        }
      }
    },
    { immediate: true },
  );
  onBeforeUnmount(() => {
    disposed = true;
    cancel();
  });
  return {
    state: computed<CatalogResults<T>>(() => ({
      query: query.value,
      entries: entries.value,
      loading: phase.value.status === "loading",
      error: phase.value.status === "failed" ? "Results could not be loaded." : "",
      hasMore: nextAfter.value !== null,
      scrollKey: scrollKey.value,
    })),
    search,
    loadMore,
    retry,
  };
}
