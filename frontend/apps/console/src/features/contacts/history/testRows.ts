import { decode } from "@/api/index.ts";
import { passOrContactReader } from "../handStarted.ts";
import type { HistoryRow } from "./history.ts";

/** A History row as the read sends it (a pass, or with `booked: false` a hand-started contact). */
export function row(o: Record<string, unknown>): HistoryRow {
  const base =
    o.booked === false
      ? {
          kind: "contact",
          realized_contact_id: o.id,
          state: "completed",
          ends_at: null,
          spacecraft: null,
          station: { ref: "FBK", id: "gs-fbk", code: "FBK", name: "Fairbanks" },
          started_by: null,
        }
      : {
          kind: "contact",
          state: "completed",
          pass_phase: null,
          delivery_state: null,
          spacecraft_id: "sc-312",
          spacecraft: { id: "sc-312", name: "EARENDIL-312", scid: 312 },
          station: { ref: "FBK", id: "gs-fbk", code: "FBK", name: "Fairbanks" },
          antenna: null,
          ends_at: "2026-11-12T03:08:52Z",
          uplink_capable: null,
          source: { provider: "p", provider_name: "Simulator", synthetic: true },
          max_elevation_deg: null,
          plan: null,
        };
  const r = decode(passOrContactReader, { ...base, ...o });
  if (!r.ok) throw new Error(r.error.message);
  return r.value;
}
