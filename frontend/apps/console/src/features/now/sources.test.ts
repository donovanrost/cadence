import { describe, expect, it } from "vite-plus/test";
import { decode, scid, spacecraftId } from "@/api/index.ts";
import { causeWords, missedPassReader, missedPassRows, type MissedItem } from "./sources.ts";

/** Missed passes (U35): causes are a known key or the provider's own reason (rule B, §12B). */
const read = <T>(reader: Parameters<typeof decode<T>>[0], raw: unknown): T => {
  const r = decode(reader, raw);
  if (!r.ok) throw new Error(r.error.message);
  return r.value;
};
const wire = {
  reservation_id: "r-0",
  station: { ref: "svb", id: "st-1", code: "SVB-1", name: "Svalbard" },
  planned_aos: "2026-11-15T03:10:00Z",
  outcome: "missed",
  cause: null,
  owner: null,
};
const missed = (i: number, cause: string | null): MissedItem => ({
  id: `m-${i}`,
  priority: 2,
  state: "caution",
  scName: `EARENDIL-00${i}`,
  spacecraftId: read(spacecraftId, `sc-${i}`),
  scid: read(scid, i),
  missed: [
    read(missedPassReader, {
      reservation_id: `r-${i}`,
      station: { ref: "svb", id: "st-1", code: "SVB-1", name: "Svalbard" },
      planned_aos: "2026-11-15T03:10:00Z",
      outcome: "missed",
      cause,
      owner: null,
    }),
  ],
  next: null,
});

describe("missed-pass causes", () => {
  it("words a known cause, and says the provider's own reason in its words", () => {
    const words = (cause: string | null) =>
      causeWords(read(missedPassReader, { ...wire, cause }).cause);
    expect(words("provider_rejected")).toBe("rejected by the provider");
    expect(words("Antenna_fault")).toBe("antenna fault");
    expect(words(null)).toBe("cause unknown");
  });

  it("groups 3+ by station and cause, and never lumps different unknown causes together", () => {
    const rows = missedPassRows(
      [
        missed(1, "antenna_fault"),
        missed(2, "antenna_fault"),
        missed(3, "antenna_fault"),
        missed(4, "rain_fade"),
        missed(5, "rain_fade"),
      ],
      6 * 3600,
    );
    expect(rows.map((r) => r.title)).toEqual([
      "3 missed passes at SVB-1 · antenna fault",
      "EARENDIL-004 · 1 missed pass at SVB-1 · rain fade",
      "EARENDIL-005 · 1 missed pass at SVB-1 · rain fade",
    ]);
  });
});
