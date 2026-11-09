import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { object, string } from "./decode.ts";
import { request, setCsrfToken } from "./http.ts";

const ok = object({ id: string });

function stubFetch(status: number, body: unknown) {
  const calls: { url: string; init: RequestInit }[] = [];
  vi.stubGlobal("fetch", (url: string, init: RequestInit) => {
    calls.push({ url, init });
    return Promise.resolve(new Response(body === null ? "" : JSON.stringify(body), { status }));
  });
  return calls;
}

afterEach(() => vi.unstubAllGlobals());

describe("request", () => {
  it("sends FormData as multipart (no JSON, no content-type) with the CSRF header", async () => {
    setCsrfToken("tok");
    const calls = stubFetch(202, { data: { id: "imp_1" } });
    const form = new FormData();
    form.append("file", new Blob(["x"]), "demo.yaml");
    const result = await request("/missions/m/catalog/imports", ok, { method: "POST", body: form });
    expect(result).toEqual({ ok: true, value: { id: "imp_1" } });
    const headers = calls[0]?.init.headers as Record<string, string>;
    expect(calls[0]?.init.body).toBe(form);
    expect(headers["content-type"]).toBeUndefined();
    expect(headers["x-csrf-token"]).toBe("tok");
  });

  it("maps 413 to invalid with a code even without an error body", async () => {
    stubFetch(413, null);
    const result = await request("/x", ok, { method: "POST", body: new FormData() });
    expect(result).toMatchObject({ ok: false, error: { kind: "invalid", code: "file_too_large" } });
  });

  it("keeps the server code on 422", async () => {
    stubFetch(422, { error: { code: "reason_required", message: "Give a reason." } });
    const result = await request("/x", ok, { method: "POST", body: {} });
    expect(result).toMatchObject({
      ok: false,
      error: { kind: "invalid", code: "reason_required" },
    });
  });
});
