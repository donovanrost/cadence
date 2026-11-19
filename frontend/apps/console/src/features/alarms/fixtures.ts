import { spacecraftId as spacecraftIdReader, scid as scidReader } from "@/api/index.ts";
import type { Episode } from "./episodes.ts";

/** A decoded alarm episode for tests (EARENDIL-312, VBAT red low, new). */
export const episodeFixture = (overrides: Partial<Episode> = {}): Episode => ({
  id: "alarm_episode_1",
  source: "ground_limit",
  status: "new",
  cleared_unacknowledged: false,
  severity: "critical",
  peak_severity: "critical",
  source_state: "red_low",
  spacecraft_id: spacecraftIdReader("sc-312"),
  spacecraft: { id: spacecraftIdReader("sc-312"), name: "EARENDIL-312", scid: scidReader(312) },
  point: { id: "EPS.VBAT", name: "VBAT", unit: "V" },
  thresholds: { red_low: 24, yellow_low: 25, yellow_high: 33, red_high: 34 },
  opened_at: "2026-11-08T02:35:02Z",
  cleared_at: null,
  first_value: 23.4,
  last_value: 23.1,
  last_observed_at: "2026-11-08T02:41:15Z",
  last_evaluated_at: "2026-11-08T02:41:00Z",
  acknowledged_at: null,
  acknowledged_by: null,
  assignee: null,
  assigned_at: null,
  limit_definition_id: undefined,
  limit_definition_version: undefined,
  limit_set_name: undefined,
  trigger: undefined,
  ...overrides,
});
