import { effectScope, nextTick, ref } from "vue";
import { describe, expect, it } from "vite-plus/test";
import type { ApiResult } from "./http.ts";
import { useRemoteQuery } from "./use-remote-query.ts";

type Deferred = { resolve: (value: ApiResult<string>) => void; signal: AbortSignal; key: string };

function harness() {
  const calls: Deferred[] = [];
  const fetcher = (key: string, signal: AbortSignal) =>
    new Promise<ApiResult<string>>((resolve) => calls.push({ resolve, signal, key }));
  return { calls, fetcher };
}

const flush = async () => {
  await Promise.resolve();
  await nextTick();
};

describe("useRemoteQuery", () => {
  it("stamps a ready value with when its request started (#395)", async () => {
    const { calls, fetcher } = harness();
    const scope = effectScope();
    const before = new Date();
    const query = scope.run(() => useRemoteQuery(ref("m1"), fetcher));
    const asked = new Date();
    calls[0]?.resolve({ ok: true, value: "one" });
    await flush();
    const state = query?.state.value;
    if (state?.status !== "ready" || !state.requestedAt) throw new Error("no requestedAt");
    expect(state.requestedAt >= before && state.requestedAt <= asked).toBe(true);
    expect(state.requestedAt <= state.receivedAt).toBe(true);
    scope.stop();
  });

  it("drops a stale response after the key changes and aborts it", async () => {
    const { calls, fetcher } = harness();
    const key = ref<string | null>("m1");
    const scope = effectScope();
    const query = scope.run(() => useRemoteQuery(key, fetcher));
    key.value = "m2";
    await nextTick();
    expect(calls[0]?.signal.aborted).toBe(true);
    calls[1]?.resolve({ ok: true, value: "two" });
    calls[0]?.resolve({ ok: true, value: "one" });
    await flush();
    expect(query?.state.value).toMatchObject({ status: "ready", value: "two" });
    scope.stop();
  });

  it("keeps the last value during a refetch and aborts on dispose", async () => {
    const { calls, fetcher } = harness();
    const scope = effectScope();
    const query = scope.run(() => useRemoteQuery(ref("m1"), fetcher));
    calls[0]?.resolve({ ok: true, value: "first" });
    await flush();
    query?.refetch();
    expect(query?.state.value).toMatchObject({ status: "ready", value: "first" });
    scope.stop();
    expect(calls[1]?.signal.aborted).toBe(true);
  });

  it("doesn't abort an in-flight read on refetch: refetches during it become one more read", async () => {
    const { calls, fetcher } = harness();
    const scope = effectScope();
    const query = scope.run(() => useRemoteQuery(ref("m1"), fetcher));
    calls[0]?.resolve({ ok: true, value: "first" });
    await flush();
    query?.refetch();
    query?.refetch();
    query?.refetch();
    expect(calls).toHaveLength(2);
    expect(calls[1]?.signal.aborted).toBe(false);
    calls[1]?.resolve({ ok: true, value: "second" });
    await flush();
    expect(query?.state.value).toMatchObject({ status: "ready", value: "second" });
    expect(calls).toHaveLength(3);
    calls[2]?.resolve({ ok: true, value: "third" });
    await flush();
    expect(query?.state.value).toMatchObject({ status: "ready", value: "third" });
    expect(calls).toHaveLength(3);
    scope.stop();
  });

  it("starts a fresh read for a refetch that comes after the read landed (no lost update)", async () => {
    const { calls, fetcher } = harness();
    const scope = effectScope();
    const query = scope.run(() => useRemoteQuery(ref("m1"), fetcher));
    calls[0]?.resolve({ ok: true, value: "first" });
    await flush();
    query?.refetch();
    calls[1]?.resolve({ ok: true, value: "second" });
    await flush();
    query?.refetch();
    expect(calls).toHaveLength(3);
    calls[2]?.resolve({ ok: true, value: "third" });
    await flush();
    expect(query?.state.value).toMatchObject({ status: "ready", value: "third" });
    scope.stop();
  });

  it("keeps the newest read's value: a follow-up queued during the follow-up runs last", async () => {
    const { calls, fetcher } = harness();
    const scope = effectScope();
    const query = scope.run(() => useRemoteQuery(ref("m1"), fetcher));
    query?.refetch(); // during the first read: one follow-up
    calls[0]?.resolve({ ok: true, value: "older" });
    await flush();
    expect(calls).toHaveLength(2);
    query?.refetch(); // during the follow-up: one more
    query?.refetch();
    calls[1]?.resolve({ ok: true, value: "newer" });
    await flush();
    expect(query?.state.value).toMatchObject({ status: "ready", value: "newer" });
    expect(calls).toHaveLength(3);
    calls[2]?.resolve({ ok: true, value: "newest" });
    await flush();
    expect(query?.state.value).toMatchObject({ status: "ready", value: "newest" });
    expect(calls).toHaveLength(3);
    scope.stop();
  });

  it("treats a new object with the same contents as the same key, and hands the fetcher the typed key", async () => {
    const seen: { m: string; page: number }[] = [];
    const fetcher = (key: { m: string; page: number }) => {
      seen.push(key);
      return Promise.resolve<ApiResult<string>>({ ok: true, value: `${key.m}:${key.page}` });
    };
    const page = ref(1);
    const tick = ref(0);
    const scope = effectScope();
    const query = scope.run(() =>
      useRemoteQuery(() => {
        void tick.value; // an unrelated dependency that rebuilds the key object
        return { m: "m1", page: page.value };
      }, fetcher),
    );
    await flush();
    tick.value += 1;
    await flush();
    expect(seen).toEqual([{ m: "m1", page: 1 }]);
    page.value = 2;
    await flush();
    expect(seen.at(-1)).toEqual({ m: "m1", page: 2 });
    expect(query?.state.value).toMatchObject({ status: "ready", value: "m1:2" });
    scope.stop();
  });
});
