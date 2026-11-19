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

  it("reads a 204 No Content through the reader with null (DELETE)", async () => {
    vi.stubGlobal("fetch", () => Promise.resolve(new Response(null, { status: 204 })));
    const result = await request("/x", () => null, { method: "DELETE" });
    expect(result).toEqual({ ok: true, value: null });
  });

  it("reads 429 as a refusal with its details (api-ops: too_many_attempts)", async () => {
    stubFetch(429, {
      error: { code: "too_many_attempts", message: "Wait.", details: { retry_after: 40 } },
    });
    const result = await request("/x", ok, { method: "PUT", body: {} });
    expect(result).toMatchObject({
      ok: false,
      error: { kind: "invalid", code: "too_many_attempts", details: { retry_after: 40 } },
    });
  });

  it("keeps a 403's details (#236: which craft the approver saved)", async () => {
    stubFetch(403, {
      error: {
        code: "activation_approver_authored_content",
        message: "x",
        details: { spacecraft_ids: ["sc_1"], spacecraft: [{ id: "sc_1", name: "EARENDIL-004" }] },
      },
    });
    const result = await request("/x", ok, { method: "POST", body: {} });
    expect(result).toMatchObject({
      ok: false,
      error: { kind: "forbidden", details: { spacecraft_ids: ["sc_1"] } },
    });
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

describe("outcomeUnknown (qa #19)", () => {
  it("treats 5xx, a dropped connection and an unreadable reply as unknown, not as failure", async () => {
    const { outcomeUnknown } = await import("./http.ts");
    expect(outcomeUnknown({ kind: "unavailable", status: 500, message: "" })).toBe(true);
    expect(outcomeUnknown({ kind: "unavailable", status: 0, message: "" })).toBe(true);
    expect(outcomeUnknown({ kind: "malformed", message: "" })).toBe(true);
    expect(outcomeUnknown({ kind: "conflict", code: "x", message: "", details: null })).toBe(false);
  });

  it("keeps a 5xx's serverCode; apply_interrupted is settled (did not land), so not unknown", async () => {
    const { outcomeUnknown, request } = await import("./http.ts");
    const { token } = await import("./decode.ts");
    vi.stubGlobal("fetch", () =>
      Promise.resolve(
        new Response(
          JSON.stringify({
            error: {
              code: "apply_interrupted",
              message: "The apply was interrupted and did not take effect. Try again.",
            },
          }),
          { status: 503 },
        ),
      ),
    );
    const result = await request("/x", token, { method: "POST", body: {} });
    expect(result).toEqual({
      ok: false,
      error: {
        kind: "unavailable",
        status: 503,
        message: "The apply was interrupted and did not take effect. Try again.",
        serverCode: "apply_interrupted",
      },
    });
    expect(!result.ok && outcomeUnknown(result.error)).toBe(false);
    expect(
      outcomeUnknown({ kind: "unavailable", status: 503, message: "", serverCode: "other" }),
    ).toBe(true);
  });
});
