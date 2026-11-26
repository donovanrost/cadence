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

/** Fetches one page after `cursor` (null: the first), at the server's page size. */
export type PageFetcher<K, Item, Meta> = (
  key: K,
  cursor: string | null,
  signal: AbortSignal,
) => Promise<ApiResult<Page<Item, Meta>>>;

export type PagedQuery<Item, Meta> = Readonly<{
  state: Readonly<ShallowRef<RemoteState<Paged<Item, Meta>>>>;
  /** Appends the next page. A no-op when there is none or one is already on its way. */
  more: () => Promise<void>;
  moreBusy: Readonly<ShallowRef<boolean>>;
  /**
   * Why the last Load more failed (the rows stay), for an alert next to the button (ux U72, a11y
   * B6). Cleared when a Load more starts, so a repeated failure is said again.
   */
  moreError: Readonly<ShallowRef<ApiError | null>>;
  /** Why the last live refresh failed while rows were shown (they stay); null after a success. */
  refreshError: Readonly<ShallowRef<ApiError | null>>;
  /** Reloads from the first page up to the rows shown, so nothing vanishes (a live change). */
  refetch: () => void;
  /**
   * True while a filter change's first page is on its way and the previous filter's rows are still
   * shown (`scopeOf`). A screen says "Updating…" beside them; Load more waits.
   */
  pending: Readonly<ShallowRef<boolean>>;
}>;

export type PagedQueryOptions<K> = Readonly<{
  /**
   * The key without its filters (e.g. the mission), for keys that carry a filter such as a search
   * box. A key change within the same scope is a filter change: the rows shown stay, `state` stays
   * ready and `pending` is set until the new first page replaces them, so a search field above the
   * list never unmounts as the person types (#903). A scope change starts over, showing loading.
   * Without it, every key change shows loading.
   */
  scopeOf?: ((key: K) => unknown) | undefined;
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
 * - A first page that fails is the state's failure (ApRemote shows it with Retry); a Retry from
 *   there loads afresh, showing loading. A Load more or a refresh that fails keeps the rows and
 *   sets `moreError` or `refreshError`.
 * - With `scopeOf`, a filter change keeps the rows shown until the new first page lands (`pending`).
 *   If that page fails, the state is the failure: the old rows don't match the new filter.
 */
export function usePagedQuery<K, Item, Meta>(
  key: MaybeRefOrGetter<K | null>,
  fetchPage: PageFetcher<K, Item, Meta>,
  idOf: (item: Item) => string,
  options: PagedQueryOptions<K> = {},
): PagedQuery<Item, Meta> {
  const state = shallowRef<RemoteState<Paged<Item, Meta>>>({ status: "loading" });
  const moreBusy = shallowRef(false);
  const moreError = shallowRef<ApiError | null>(null);
  const refreshError = shallowRef<ApiError | null>(null);
  const pending = shallowRef(false);
  /** The scope of the rows shown (`scopeOf`), compared as JSON like the key; null when none is. */
  let shownScope: string | null = null;
  const scopeSignature = (current: K) =>
    options.scopeOf ? JSON.stringify(options.scopeOf(current)) : null;
  let controller: AbortController | null = null;
  /** Bumped by every start-over and refresh: a page from before is dropped. */
  let generation = 0;
  let refreshing = false;
  let again = false;

  const dedupe = (items: readonly Item[]) => [
    ...new Map(items.map((item) => [idOf(item), item])).values(),
  ];

  /**
   * Pages from the first until `upTo` items are back (at least one page). `fresh` shows loading;
   * `refresh` keeps the rows and a failure is `refreshError`; `filter` keeps the rows while
   * `pending` and a failure is the state's.
   */
  async function load(current: K, upTo: number, mode: "fresh" | "refresh" | "filter") {
    controller?.abort();
    const mine = new AbortController();
    controller = mine;
    const id = ++generation;
    moreBusy.value = false;
    pending.value = mode === "filter";
    const keep = mode !== "fresh";
    if (!keep) state.value = { status: "loading" };
    const requestedAt = new Date();
    const items: Item[] = [];
    const metas: Meta[] = [];
    /** The first page, once it arrived: its meta is the list's (a Meta may itself be undefined). */
    let first: { meta: Meta } | null = null;
    let cursor: string | null = null;
    do {
      const result = await fetchPage(current, cursor, mine.signal);
      if (id !== generation) return;
      if (!result.ok) {
        pending.value = false;
        if (mode === "refresh" && state.value.status === "ready") refreshError.value = result.error;
        else {
          state.value = { status: "failed", error: result.error };
          shownScope = null;
        }
        return;
      }
      items.push(...result.value.items);
      metas.push(result.value.meta);
      first ??= { meta: result.value.meta };
      cursor = result.value.next;
    } while (cursor !== null && items.length < upTo);
    if (first === null) return;
    refreshError.value = null;
    pending.value = false;
    shownScope = scopeSignature(current);
    state.value = {
      status: "ready",
      value: { items: dedupe(items), next: cursor, meta: first.meta, metas },
      receivedAt: new Date(),
      requestedAt,
    };
  }

  async function refresh(current: K) {
    refreshing = true;
    try {
      // Shown rows stay while they reload; from a failure (Retry) it loads afresh. During a filter
      // change the rows shown are the old filter's: it is still that change's first page.
      const s = state.value;
      if (pending.value) await load(current, 0, "filter");
      else if (s.status === "ready") await load(current, s.value.items.length, "refresh");
      else await load(current, 0, "fresh");
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
    if (
      s.status !== "ready" ||
      s.value.next === null ||
      current === null ||
      moreBusy.value ||
      pending.value
    )
      return;
    const id = generation;
    moreBusy.value = true;
    moreError.value = null;
    try {
      const signal = controller?.signal ?? new AbortController().signal;
      const result = await fetchPage(current, s.value.next, signal);
      if (id !== generation) return;
      if (!result.ok) {
        moreError.value = result.error;
        return;
      }
      state.value = {
        ...s,
        value: {
          items: dedupe([...s.value.items, ...result.value.items]),
          next: result.value.next,
          meta: s.value.meta,
          metas: [...s.value.metas, result.value.meta],
        },
        // `receivedAt` stays the first page's: older pages don't make the newest rows any fresher.
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
      moreError.value = null;
      refreshError.value = null;
      again = false;
      if (signature === null || current === null) {
        controller?.abort();
        generation += 1;
        moreBusy.value = false;
        pending.value = false;
        shownScope = null;
        state.value = { status: "loading" };
        return;
      }
      // Rows of the same scope are shown: a filter change keeps them until its first page lands.
      const filterOnly =
        state.value.status === "ready" &&
        shownScope !== null &&
        shownScope === scopeSignature(current);
      void load(current, 0, filterOnly ? "filter" : "fresh").catch(() => undefined);
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
    moreError,
    refreshError,
    pending,
    refetch: () => {
      const current = toValue(key);
      if (current === null) return;
      if (refreshing) again = true;
      else void refresh(current);
    },
  };
}
