import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import type { Attention } from "./attention.ts";
import { NO_ACCESS, retryTargets } from "./useQueueCommand.ts";

const target = (id: string) =>
  ({ id, source: "contact_settlement" }) as Pick<Attention, "id" | "source">;
const reply = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
const err = (code: string, message: string) => ({ error: { code, message } });

describe("Retry storing (domain #71 final contract)", () => {
  afterEach(() => vi.unstubAllGlobals());
  const stub = (...replies: Response[]) => {
    const fetch = vi.fn();
    for (const r of replies) fetch.mockResolvedValueOnce(r);
    vi.stubGlobal("fetch", fetch);
    return fetch;
  };
  // The 200 body is the attention object; an empty object fails decoding, so reuse 409 for "ok-ish".
  it("counts 409 retry_not_manual as retried and drops a 404", async () => {
    stub(
      reply(409, err("retry_not_manual", "Already retrying.")),
      reply(404, err("attention_item_not_found", "Gone.")),
      reply(409, err("retry_not_manual", "Already retrying.")),
    );
    expect(await retryTargets("m", [target("a"), target("b"), target("c")] as Attention[])).toBe(
      "Retried 2.",
    );
  });

  it("names a failure with the server's sentence, and 403 reads the operators line", async () => {
    stub(
      reply(409, err("retry_not_manual", "x")),
      reply(422, err("invalid_params", "Replay is busy.")),
    );
    expect(await retryTargets("m", [target("a"), target("b")] as Attention[])).toBe(
      "Retried 1 of 2. 1 failed: Replay is busy.",
    );
    stub(reply(403, err("forbidden", "No.")));
    expect(await retryTargets("m", [target("a")] as Attention[])).toBe(NO_ACCESS);
    stub(reply(409, err("retry_not_manual", "x")));
    expect(await retryTargets("m", [target("a")] as Attention[])).toBeNull();
  });
});
