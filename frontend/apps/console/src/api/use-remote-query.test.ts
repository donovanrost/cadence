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
});
