import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { missionId as missionIdReader, decode } from "@/api/index.ts";
import { attentionReader, type Attention } from "./attention.ts";
import { NO_ACCESS, NO_ACCESS_SEEN, retryTargets, seenTargets } from "./useQueueCommand.ts";

// domain's #71 sample item (refs shortened), as the queue and the retry endpoint send it.
const sample = (id: string, retry: string) => ({
  id,
  source: "contact_settlement",
  conflict: "unsettled",
  state: "open",
  acknowledged_by: null,
  contact_id: "scheduled_contact_cd34",
  reservation_id: `res-${id}`,
  station: { ref: "svb", id: "st-1", code: "SVA", name: "Svalbard" },
  provider: { id: "p-1", name: "Northlight" },
  starts_at: "2026-11-11T18:49:00Z",
  ends_at: "2026-11-11T18:57:00Z",
  raised_at: "2026-11-12T00:57:00Z",
  deadline_at: "2026-11-12T00:57:00Z",
  backlog: { entries: 1204, bytes: 3355443, journals: 1 },
  failure_kind: "telemetry_storage_unavailable",
  failure_message: null,
  retry,
  attempts: retry === "manual" ? 6 : 0,
  next_attempt_at: retry === "manual" ? null : "2026-11-11T23:20:00Z",
  last_attempt_at: "2026-11-11T23:10:00Z",
  provider_message: null,
  resolution: null,
});
const read = (raw: unknown): Attention => {
  const r = decode(attentionReader, raw);
  if (!r.ok) throw new Error(r.error.message);
  return r.value;
};
const manual = (id: string) => read(sample(id, "manual"));
const reply = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
const err = (code: string, message: string, details?: unknown) => ({
  error: { code, message, ...(details === undefined ? {} : { details }) },
});

describe("Retry storing (domain #71 final contract, ux c10265fd review)", () => {
  afterEach(() => vi.unstubAllGlobals());
  const stub = (...replies: Response[]) => {
    const fetch = vi.fn();
    for (const r of replies) fetch.mockResolvedValueOnce(r);
    vi.stubGlobal("fetch", fetch);
  };

  it("takes 200's item and 409's details.item as retried; a 404 drops out; an emptied fold", async () => {
    stub(
      reply(200, { data: sample("a", "automatic") }),
      reply(409, err("retry_not_manual", "Already retrying.", { item: sample("b", "automatic") })),
      reply(404, err("attention_item_not_found", "Gone.")),
    );
    const out = await retryTargets(missionIdReader("m"), [manual("a"), manual("b"), manual("c")]);
    expect(out.text).toBe("Retried 2.");
    expect(out.emptied).toBe(true);
    expect(out.items.map((a) => [a.id, a.retry])).toEqual([
      ["a", "automatic"],
      ["b", "automatic"],
    ]);
  });

  it("names a failure with the server's sentence; 403 reads the operators line", async () => {
    stub(
      reply(200, { data: sample("a", "automatic") }),
      reply(422, err("invalid_params", "Replay is busy.")),
    );
    const partial = await retryTargets(missionIdReader("m"), [manual("a"), manual("b")]);
    expect([partial.text, partial.emptied]).toEqual([
      "Retried 1 of 2. 1 failed: Replay is busy.",
      false,
    ]);
    stub(reply(403, err("forbidden", "No.")));
    expect((await retryTargets(missionIdReader("m"), [manual("a")])).text).toBe(NO_ACCESS);
    stub(reply(200, { data: sample("a", "automatic") }));
    const single = await retryTargets(missionIdReader("m"), [manual("a")]);
    expect([single.text, single.emptied, single.items.length]).toEqual([null, false, 1]);
  });

  it("Mark as seen takes the returned item; 404 is silent; 403 reads the operators line", async () => {
    const seen = { ...sample("a", "manual"), resolution: null, state: "acknowledged" };
    stub(reply(200, { data: seen }));
    const ok = await seenTargets(missionIdReader("m"), [manual("a")]);
    expect([ok.text, ok.items.map((a) => a.state)]).toEqual([null, ["acknowledged"]]);
    stub(reply(404, err("attention_item_not_found", "Gone.")));
    expect((await seenTargets(missionIdReader("m"), [manual("a")])).text).toBeNull();
    stub(reply(403, err("forbidden", "No.")));
    expect((await seenTargets(missionIdReader("m"), [manual("a")])).text).toBe(NO_ACCESS_SEEN);
  });
});
