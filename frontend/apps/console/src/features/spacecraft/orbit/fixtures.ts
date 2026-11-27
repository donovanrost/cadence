/** Wire fixtures for the Orbit section's tests (element-sets.md, predicted-passes.md). */
export const elementSetWire = (over: Record<string, unknown> = {}) => ({
  id: "elset_2",
  spacecraft_id: "sc-312",
  format: "tle",
  source: "manual",
  epoch: "2026-11-26T12:00:00.000000Z",
  object_name: "EARENDIL-312",
  norad_id: 25544,
  element_set_number: 292,
  elements: { mean_motion_rev_per_day: 15.7, eccentricity: 0.0006 },
  content_sha256: "abc",
  raw: "1 25544U …",
  received_at: "2026-11-26T13:00:00.000000Z",
  created_by: { kind: "user", id: "u-1", name: "Mira K." },
  ...over,
});

export const passWire = (over: Record<string, unknown> = {}) => ({
  id: "predicted_pass_1",
  aos: "2026-11-27T00:41:12.000000Z",
  tca: "2026-11-27T00:46:30.000000Z",
  los: "2026-11-27T00:51:49.000000Z",
  max_elevation_deg: 38.24,
  aos_azimuth_deg: 201.4,
  los_azimuth_deg: 77.9,
  spacecraft: { id: "sc-312", name: "EARENDIL-312", scid: 312 },
  station: { id: "ground_station_sva", display_name: "Svalbard", code: "SVA" },
  element_set: { id: "elset_2", epoch: "2026-11-26T12:00:00.000000Z" },
  computed_at: "2026-11-27T00:00:00.000000Z",
  ...over,
});

export const coverageWire = (
  over: Record<string, unknown> = {},
  unpredicted: Record<string, number> = {},
) => ({
  horizon_end: "2026-12-04T00:00:00.000000Z",
  computed_at: "2026-11-27T00:00:00.000000Z",
  unpredicted: {
    spacecraft_without_element_set: 0,
    spacecraft_deep_space: 0,
    stations_without_location: 0,
    passes_not_bracketed: 0,
    ...unpredicted,
  },
  ...over,
});
