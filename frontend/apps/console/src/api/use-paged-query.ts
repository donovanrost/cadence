import {
  onScopeDispose,
  shallowRef,
  toValue,
  watch,
  type MaybeRefOrGetter,
  type ShallowRef,
} from "vue";
import type { ApiError, ApiResult } from "./http.ts";
import type { RemoteState } from "./remote-state.ts";

/** One page of a cursor-paged read: its items, the next page's cursor (null on the last), and the rest of the page. */
export type Page<Item, Meta> = Readonly<{
  items: readonly Item[];
  next: string | null;
  meta: Meta;
}>;

/** The pages shown so far, as one list. `meta` is the first page's; `metas` has every page's. */
export type Paged<Item, Meta> = Readonly<{
  items: readonly Item[];
  next: string | null;
  meta: Meta;
  metas: readonly Meta[];
}>;

/**
 * Fetches one page after `cursor` (null: the first). `want` is how many more items the caller
 * would like, for a read that takes a page size (a refresh asks for the rows already shown).
 */
export type PageFetcher<K, Item, Meta> = (
  key: K,
  cursor: string | null,
  want: number,
  signal: AbortSignal,
) => Promise<ApiResult<Page<Item, Meta>>>;

export type PagedQuery<Item, Meta> = Readonly<{
  state: Readonly<ShallowRef<RemoteState<Paged<Item, Meta>>>>;
  /** Appends the next page. A no-op when there is none or one is already on its way. */
  more: () => Promise<void>;
  moreBusy: Readonly<ShallowRef<boolean>>;
  /** Why the last Load more or refresh failed while rows were shown (they stay); null after a success. */
  error: Readonly<ShallowRef<ApiError | null>>;
  /** Reloads from the first page up to the rows shown, so nothing vanishes (a live change). */
  refetch: () => void;
}>;

/**
 * A cursor-paged read (ux U72), the paged counterpart of useRemoteQuery, with its rules: a `key`
 * change (null pauses) starts over at the first page and aborts what was in flight, a late answer
 * is ignored, and a refetch while one is in flight asks for one more when it lands.
 *
 * - **Load more** appends the next page.
 * - **Refetch** (a live change) walks from the first page until the rows already shown are back,
 *   showing the old rows until then, so a row that moved between pages while the list was open
 *   comes back by itself. A refetch drops a Load more still on its way.
 * - Items are kept once by `idOf`: a row that moves between pages shows once, at its first place,
 *   with its newest value.
 * - A first page that fails is the state's failure (ApRemote shows it with Retry). A refresh or
 *   Load more that fails keeps the rows and sets `error`.
 */
export function usePagedQuery<K, Item, Meta>(
  key: MaybeRefOrGetter<K | null>,
  fetchPage: PageFetcher<K, Item, Meta>,
  idOf: (item: Item) => string,
): PagedQuery<Item, Meta> {
  const state = shallowRef<RemoteState<Paged<Item, Meta>>>({ status: "loading" });
  const moreBusy = shallowRef(false);
  const error = shallowRef<ApiError | null>(null);
  let controller: AbortController | null = null;
  /** Bumped by every start-over and refresh: a page from before is dropped. */
  let generation = 0;
  let refreshing = false;
  let again = false;

  const dedupe = (items: readonly Item[]) => [
    ...new Map(items.map((item) => [idOf(item), item])).values(),
  ];

  /** Pages from the first until `upTo` items are back (at least one page). */
  async function load(current: K, upTo: number, keep: boolean) {
    controller?.abort();
    const mine = new AbortController();
    controller = mine;
    const id = ++generation;
    moreBusy.value = false;
    if (!keep) state.value = { status: "loading" };
    const requestedAt = new Date();
    const items: Item[] = [];
    const metas: Meta[] = [];
    let cursor: string | null = null;
    do {
      const result = await fetchPage(
        current,
        cursor,
        Math.max(1, upTo - items.length),
        mine.signal,
      );
      if (id !== generation) return;
      if (!result.ok) {
        if (keep && state.value.status === "ready") error.value = result.error;
        else state.value = { status: "failed", error: result.error };
        return;
      }
      items.push(...result.value.items);
      metas.push(result.value.meta);
      cursor = result.value.next;
    } while (cursor !== null && items.length < upTo);
    const [meta] = metas;
    if (meta === undefined) return;
    error.value = null;
    state.value = {
      status: "ready",
      value: { items: dedupe(items), next: cursor, meta, metas },
      receivedAt: new Date(),
      requestedAt,
    };
  }

  async function refresh(current: K) {
    refreshing = true;
    try {
      const s = state.value;
      await load(current, s.status === "ready" ? s.value.items.length : 0, true);
    } catch {
      // An aborted request (a key change started over): that load owns the state now.
    } finally {
      refreshing = false;
    }
    if (again) {
      again = false;
      const now = toValue(key);
      if (now !== null) void refresh(now);
    }
  }

  async function more() {
    const s = state.value;
    const current = toValue(key);
    if (s.status !== "ready" || s.value.next === null || current === null || moreBusy.value) return;
    const id = generation;
    moreBusy.value = true;
    try {
      const signal = controller?.signal ?? new AbortController().signal;
      const result = await fetchPage(current, s.value.next, 1, signal);
      if (id !== generation) return;
      if (!result.ok) {
        error.value = result.error;
        return;
      }
      error.value = null;
      state.value = {
        ...s,
        value: {
          items: dedupe([...s.value.items, ...result.value.items]),
          next: result.value.next,
          meta: s.value.meta,
          metas: [...s.value.metas, result.value.meta],
        },
        receivedAt: new Date(),
      };
    } catch {
      // Aborted by a start-over.
    } finally {
      if (id === generation) moreBusy.value = false;
    }
  }

  // A new object with the same contents is the same key: watch its signature (useRemoteQuery).
  watch(
    () => {
      const current = toValue(key);
      return current === null ? null : JSON.stringify(current);
    },
    (signature) => {
      const current = toValue(key);
      error.value = null;
      again = false;
      if (signature === null || current === null) {
        controller?.abort();
        generation += 1;
        moreBusy.value = false;
        state.value = { status: "loading" };
        return;
      }
      void load(current, 0, false).catch(() => undefined);
    },
    { immediate: true },
  );

  onScopeDispose(() => {
    generation += 1;
    controller?.abort();
  });

  return {
    state,
    more,
    moreBusy,
    error,
    refetch: () => {
      const current = toValue(key);
      if (current === null) return;
      if (refreshing) again = true;
      else void refresh(current);
    },
  };
}
