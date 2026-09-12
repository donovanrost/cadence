import { onBeforeUnmount, shallowRef, watch } from "vue";
type PageRegistration = {
  readonly id: string;
  readonly slot: string;
  readonly version: number;
  readonly read: unknown;
};
export type LazySource<T> = {
  has?(id: string): boolean;
  peek(id: string): T | undefined;
  load(id: string): Promise<T>;
};

export function createPageRegistry<T extends PageRegistration>(
  slot: string,
  loaders: Record<string, () => Promise<T>>,
  admit?: (items: readonly T[]) => Record<string, T>,
) {
  const values = new Map<string, T>();
  const pending = new Map<string, Promise<T>>();
  return {
    ids: Object.freeze(Object.keys(loaders)),
    has: (id: string) => Object.hasOwn(loaders, id),
    peek: (id: string) => values.get(id),
    async load(id: string): Promise<T> {
      const cached = values.get(id);
      if (cached) return cached;
      const existing = pending.get(id);
      if (existing) return existing;
      const loader = Object.hasOwn(loaders, id) ? loaders[id] : undefined;
      if (!loader) throw Error("Unknown page contribution.");
      const request = loader()
        .then((value) => {
          if (
            value.id !== id ||
            value.slot !== slot ||
            value.version !== 1 ||
            typeof value.read !== "function"
          )
            throw Error("Loaded contribution does not match its declared placement.");
          const admitted = admit ? admit([value])[id] : value;
          if (!admitted) throw Error("Loaded contribution was not admitted.");
          values.set(id, admitted);
          return admitted;
        })
        .finally(() => {
          pending.delete(id);
        });
      pending.set(id, request);
      return request;
    },
  };
}

type LoadState<T> = { kind: "loading" } | { kind: "ready"; value: T } | { kind: "failed" };
export function useLazyPage<T>(
  id: () => string,
  source: LazySource<T>,
  report: (cause: unknown) => void,
  timeoutMs = 15_000,
) {
  const state = shallowRef<LoadState<T>>({ kind: "loading" });
  let active = true,
    generation = 0;
  let timeout: ReturnType<typeof setTimeout> | undefined;
  async function load() {
    const current = ++generation,
      key = id();
    clearTimeout(timeout);
    if (source.has && !source.has(key)) {
      state.value = { kind: "failed" };
      report(Error("Unknown page contribution."));
      return;
    }
    const cached = source.peek(key);
    if (cached) {
      state.value = { kind: "ready", value: cached };
      return;
    }
    state.value = { kind: "loading" };
    try {
      const value = await Promise.race([
        source.load(key),
        new Promise<never>((_, reject) => {
          timeout = setTimeout(() => reject(Error("Page load timed out.")), timeoutMs);
        }),
      ]);
      if (active && current === generation) state.value = { kind: "ready", value };
    } catch (cause) {
      if (active && current === generation) {
        state.value = { kind: "failed" };
        report(cause);
      }
    } finally {
      if (current === generation) clearTimeout(timeout);
    }
  }
  watch(
    id,
    () => {
      void load();
    },
    { immediate: true, flush: "sync" },
  );
  onBeforeUnmount(() => {
    active = false;
    generation++;
    clearTimeout(timeout);
  });
  return {
    state,
    reload: () => {
      if (active) void load();
    },
  };
}
