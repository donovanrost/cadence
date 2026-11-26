import { effectScope, nextTick, ref } from "vue";
import { describe, expect, it } from "vite-plus/test";
import type { ApiResult } from "./http.ts";
import { usePagedQuery, type Page } from "./use-paged-query.ts";

type Row = Readonly<{ id: string; v: number }>;
type Call = Readonly<{
  key: string;
  cursor: string | null;
  signal: AbortSignal;
  resolve: (value: ApiResult<Page<Row, string>>) => void;
}>;

/** Every page request waits until the test answers it. */
function harness() {
  const calls: Call[] = [];
  const fetchPage = (key: string, cursor: string | null, signal: AbortSignal) =>
    new Promise<ApiResult<Page<Row, string>>>((resolve) =>
      calls.push({ key, cursor, signal, resolve }),
    );
  return { calls, fetchPage };
}

const rows = (...ids: string[]) => ids.map((id) => ({ id, v: 1 }));
const page = (items: Row[], next: string | null, meta = "m"): ApiResult<Page<Row, string>> => ({
  ok: true,
  value: { items, next, meta },
});
const failed: ApiResult<never> = {
  ok: false,
  error: { kind: "unavailable", status: 503, message: "down" },
};
const flush = async () => {
  for (let i = 0; i < 4; i++) await Promise.resolve();
  await nextTick();
};

function start(key = ref<string | null>("k")) {
  const h = harness();
  const scope = effectScope();
  const query = scope.run(() => usePagedQuery(key, h.fetchPage, (r) => r.id));
  if (!query) throw new Error("no query");
  return { ...h, key, scope, query };
}

const items = (q: ReturnType<typeof start>["query"]) =>
  q.state.value.status === "ready" ? q.state.value.value.items.map((r) => r.id) : null;

describe("usePagedQuery (#176)", () => {
  it("loads the first page, then Load more appends the next", async () => {
    const t = start();
    expect(t.query.state.value.status).toBe("loading");
    t.calls[0]?.resolve(page(rows("a", "b"), "c2", "first"));
    await flush();
    expect(items(t.query)).toEqual(["a", "b"]);

    const more = t.query.more();
    expect(t.query.moreBusy.value).toBe(true);
    expect(t.calls[1]?.cursor).toBe("c2");
    t.calls[1]?.resolve(page(rows("c"), null, "second"));
    await more;
    expect(items(t.query)).toEqual(["a", "b", "c"]);
    const s = t.query.state.value;
    expect(s.status === "ready" && [s.value.meta, s.value.metas, s.value.next]).toEqual([
      "first",
      ["first", "second"],
      null,
    ]);
    expect(t.query.moreBusy.value).toBe(false);
    t.scope.stop();
  });

  it("Load more keeps the first page's receivedAt: older pages don't make the newest rows fresher", async () => {
    const t = start();
    t.calls[0]?.resolve(page(rows("a"), "c2"));
    await flush();
    const before = t.query.state.value;
    if (before.status !== "ready") throw new Error("not ready");
    const more = t.query.more();
    t.calls[1]?.resolve(page(rows("b"), null));
    await more;
    const after = t.query.state.value;
    expect(after.status === "ready" && after.receivedAt).toBe(before.receivedAt);
    t.scope.stop();
  });

  it("shows a row that moved between pages once, at its first place with its newest value", async () => {
    const t = start();
    t.calls[0]?.resolve(page(rows("a", "b"), "c2"));
    await flush();
    const more = t.query.more();
    t.calls[1]?.resolve(
      page(
        [
          { id: "b", v: 2 },
          { id: "c", v: 1 },
        ],
        null,
      ),
    );
    await more;
    const s = t.query.state.value;
    expect(s.status === "ready" && s.value.items).toEqual([
      { id: "a", v: 1 },
      { id: "b", v: 2 },
      { id: "c", v: 1 },
    ]);
    t.scope.stop();
  });

  it("a refetch walks from the first page until the rows shown are back, keeping them meanwhile", async () => {
    const t = start();
    t.calls[0]?.resolve(page(rows("a", "b"), "c2"));
    await flush();
    const more = t.query.more();
    t.calls[1]?.resolve(page(rows("c", "d"), "c3"));
    await more;

    t.query.refetch();
    expect(t.calls[2]).toMatchObject({ cursor: null });
    expect(items(t.query)).toEqual(["a", "b", "c", "d"]);
    t.calls[2]?.resolve(page(rows("new", "a"), "r2"));
    await flush();
    expect(t.calls[3]).toMatchObject({ cursor: "r2" });
    t.calls[3]?.resolve(page(rows("b", "c"), "r3"));
    await flush();
    expect(items(t.query)).toEqual(["new", "a", "b", "c"]);
    const s = t.query.state.value;
    expect(s.status === "ready" && s.value.next).toBe("r3");
    t.scope.stop();
  });

  it("a refetch while one is in flight asks for one more when it lands", async () => {
    const t = start();
    t.calls[0]?.resolve(page(rows("a"), null));
    await flush();
    t.query.refetch();
    t.query.refetch();
    t.query.refetch();
    expect(t.calls).toHaveLength(2);
    t.calls[1]?.resolve(page(rows("a"), null));
    await flush();
    expect(t.calls).toHaveLength(3);
    t.calls[2]?.resolve(page(rows("a", "b"), null));
    await flush();
    expect(items(t.query)).toEqual(["a", "b"]);
    t.scope.stop();
  });

  it("a key change starts over, aborts what was in flight and drops a late Load more", async () => {
    const t = start();
    t.calls[0]?.resolve(page(rows("a"), "c2"));
    await flush();
    const more = t.query.more();
    t.key.value = "k2";
    await nextTick();
    expect(t.query.state.value.status).toBe("loading");
    expect(t.calls[1]?.signal.aborted).toBe(true);
    t.calls[2]?.resolve(page(rows("x"), null));
    t.calls[1]?.resolve(page(rows("late"), null));
    await more;
    await flush();
    expect(items(t.query)).toEqual(["x"]);
    expect(t.query.moreBusy.value).toBe(false);
    t.scope.stop();
  });

  it("a failing first page is the state's failure", async () => {
    const t = start();
    t.calls[0]?.resolve(failed);
    await flush();
    expect(t.query.state.value).toMatchObject({ status: "failed", error: { status: 503 } });
    t.scope.stop();
  });

  it("a failing Load more keeps the rows and says so until the next Load more starts", async () => {
    const t = start();
    t.calls[0]?.resolve(page(rows("a"), "c2"));
    await flush();
    const first = t.query.more();
    t.calls[1]?.resolve(failed);
    await first;
    expect(items(t.query)).toEqual(["a"]);
    expect(t.query.moreError.value).toMatchObject({ status: 503 });
    expect(t.query.refreshError.value).toBeNull();

    // Cleared as the next Load more starts, so a repeated failure is said again.
    const second = t.query.more();
    expect(t.query.moreError.value).toBeNull();
    t.calls[2]?.resolve(page(rows("b"), null));
    await second;
    expect(items(t.query)).toEqual(["a", "b"]);
    t.scope.stop();
  });

  it("a failing refresh keeps the rows and sets refreshError until one succeeds", async () => {
    const t = start();
    t.calls[0]?.resolve(page(rows("a"), null));
    await flush();
    t.query.refetch();
    t.calls[1]?.resolve(failed);
    await flush();
    expect(items(t.query)).toEqual(["a"]);
    expect(t.query.refreshError.value).toMatchObject({ status: 503 });
    expect(t.query.moreError.value).toBeNull();

    t.query.refetch();
    t.calls[2]?.resolve(page(rows("a"), null));
    await flush();
    expect(t.query.refreshError.value).toBeNull();
    t.scope.stop();
  });

  it("Retry from a failed first page loads afresh, showing loading", async () => {
    const t = start();
    t.calls[0]?.resolve(failed);
    await flush();
    expect(t.query.state.value.status).toBe("failed");
    t.query.refetch();
    expect(t.query.state.value.status).toBe("loading");
    t.calls[1]?.resolve(page(rows("a"), null));
    await flush();
    expect(items(t.query)).toEqual(["a"]);
    t.scope.stop();
  });

  it("a null key pauses: nothing is fetched and refetch does nothing", async () => {
    const t = start(ref<string | null>(null));
    t.query.refetch();
    await t.query.more();
    expect(t.calls).toHaveLength(0);
    expect(t.query.state.value.status).toBe("loading");
    t.scope.stop();
  });
});
