import { describe, expect, it } from "vite-plus/test";
import { missionId as missionIdReader } from "@/api/index.ts";
import { fetchSummary } from "./api.ts";
import {
  byRealization,
  bytes,
  causeText,
  fillDays,
  freshnessMeta,
  headline,
  ownerCaption,
  percent,
  provisionalText,
} from "./format.ts";

// The summary reader isn't exported; read it through a fake fetch of the live payload's shape.
const payload = {
  from: "2026-11-03T00:00:00.000Z",
  to: "2026-11-10T00:00:00.000Z",
  planned: 10,
  realized: 0,
  partial: 10,
  missed: 0,
  canceled: 0,
  pending_count: 0,
  realized_ratio: 0,
  threshold: 0.95,
  target: 0.98,
  provisional: false,
  missed_by_owner: {},
  partial_by_owner: { us: 10 },
  by_station: [
    {
      provider: { id: "p", name: "Demo", account_id: "a" },
      station: { code: "PUQ", id: "s1", name: "Punta Arenas", ref: "s1" },
      planned: 3,
      realized: 0,
      partial: 3,
      missed: 0,
      canceled: 0,
      planned_seconds: 1440,
      flown_seconds: 1437,
    },
  ],
  by_cause: [
    { cause: "not_ingested", owner: "us", partial: 10, missed: 0, cause_source: "cadence" },
  ],
  plans: [{ id: "contact_plan_x", version: 1 }],
  freshness: [
    {
      provider: { id: "p", name: "Demo", account_id: "a" },
      provider_id: "p",
      cursor_healthy: true,
      pending_reports: 0,
      last_report_at: "2026-11-09T15:41:35.030446Z",
      oldest_pending_los: null,
    },
  ],
};

async function summary(body: unknown = payload) {
  const fetchMock = async () => new Response(JSON.stringify({ data: body }), { status: 200 });
  const original = globalThis.fetch;
  globalThis.fetch = fetchMock as typeof fetch;
  try {
    const r = await fetchSummary(
      { missionId: missionIdReader("m"), day: "2026-11-09", span: "week" },
      new AbortController().signal,
    );
    if (!r.ok) throw new Error(JSON.stringify(r.error));
    return r.value;
  } finally {
    globalThis.fetch = original;
  }
}

describe("pass review summary", () => {
  it("reads the live shape: sparse owners and a missing failed count", async () => {
    const s = await summary();
    expect(s.failed).toBe(0);
    expect(s.missed_by_owner).toEqual({ provider: 0, us: 0, weather: 0, unknown: 0 });
    expect(ownerCaption(s.partial_by_owner)).toBe("10 on our side");
    expect(ownerCaption(s.missed_by_owner)).toBeUndefined();
  });
  it("says the verdict against the target, and freshness in words", async () => {
    const s = await summary();
    expect(headline(s)).toEqual({ text: "0% realized", tone: "caution" });
    expect(headline({ ...s, realized_ratio: 0.985 })).toEqual({
      text: "98.5% realized",
      tone: "nominal",
    });
    expect(headline({ ...s, realized_ratio: null }).tone).toBe("off");
    expect(freshnessMeta(s)).toBe("Reports in from the provider · last at 15:41Z · 0 pending");
    expect(provisionalText(s)).toBeNull();
    expect(provisionalText({ ...s, provisional: true, pending_count: 2 })).toBe(
      "Provisional: 2 passes await a provider report.",
    );
  });
  it("sorts stations by realization, worst first", async () => {
    const s = await summary();
    const [bad] = s.by_station;
    if (!bad) throw new Error("no station line");
    const good = { ...bad, realized: 3, partial: 0 };
    expect(byRealization([good, bad])[0]).toBe(bad);
  });
});

describe("format", () => {
  it("formats percent, bytes and causes", () => {
    expect(percent(0.98)).toBe("98%");
    expect(percent(null)).toBe("—");
    expect(bytes(6_943_105)).toBe("6.9 MB");
    expect(bytes(0)).toBe("0 B");
    expect(bytes(null)).toBe("—");
    expect(causeText("not_ingested")).toBe("Delivered, not ingested");
    expect(causeText("rain_fade")).toBe("Rain fade");
  });
  it("fills 30 days ending at the chosen day", () => {
    const days = fillDays(
      [
        {
          day: "2026-11-09",
          planned: 10,
          realized: 0,
          canceled: 0,
          pending: 0,
          ratio: undefined,
          realized_ratio: 0,
          top_cause: null,
          top_station: null,
        },
      ],
      "2026-11-09",
    );
    expect(days).toHaveLength(30);
    expect(days[0]?.day).toBe("2026-10-11");
    expect(days.at(-1)?.entry?.planned).toBe(10);
    expect(days[0]?.entry).toBeNull();
  });
});

describe("pass review nulls (api drift sweep 11-13)", () => {
  it("reads a provider-less freshness row, an unknown cursor and a station without a ref", async () => {
    const [line] = payload.by_station;
    const [fresh] = payload.freshness;
    if (!line || !fresh) throw new Error("fixture");
    const s = await summary({
      ...payload,
      provisional: true,
      pending_count: 1,
      by_station: [{ ...line, station: { ...line.station, ref: null } }],
      freshness: [{ ...fresh, provider: null, cursor_healthy: null, pending_reports: 1 }],
    });
    expect(s.by_station[0]?.station.ref).toBeNull();
    // Unknown cursor health isn't called broken; the provider is named generically.
    expect(provisionalText(s)).toBe("Provisional: 1 pass awaits a provider report (a provider).");
  });
});
