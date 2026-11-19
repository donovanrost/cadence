/** (B) wire fixtures (api's shape diff), for tests and the preview; never shipped as data. */
export const documentWire = (o: Record<string, unknown> = {}) => ({
  catalog_revision_id: "cr-14",
  telemetry_source_endpoint_id: "src-1",
  handled_apids: [42, 43],
  protocol: {
    downlink: "tm",
    uplink: "tc",
    frame_size: 1115,
    secondary_header_length: 0,
    insert_zone_length: 0,
    ocf_length: 4,
    truncated_primary_header: false,
  },
  ...o,
});

export const snapshotWire = (o: Record<string, unknown> = {}) => ({
  spacecraft_id: "spacecraft-earendil-004",
  name: "EARENDIL-004",
  scid: 4,
  section: "overview",
  token: "t-1",
  saved_version: 4,
  document: documentWire(),
  external_changes: false,
  active: { version: 3, generation: 9, document: documentWire({ handled_apids: [42] }) },
  review: null,
  approval: {
    requirement: "independent",
    policy_token: "p-1",
    source: "organization",
    can_request: true,
    can_review: false,
  },
  catalogs: [
    {
      id: "cr-14",
      name: "EARENDIL FSW",
      label: "catalog rev 14",
      declarations: 812,
      packets: 40,
      commands: 120,
    },
  ],
  fleet: [
    {
      id: "spacecraft-earendil-004",
      name: "EARENDIL-004",
      scid: 4,
      active_catalog_id: "cr-14",
      has_changes: true,
    },
    {
      id: "spacecraft-earendil-005",
      name: "EARENDIL-005",
      scid: 5,
      active_catalog_id: "cr-14",
      has_changes: false,
    },
  ],
  fleet_total: 2,
  sources: [{ id: "src-1", name: "SVA S-band" }],
  presets: [],
  switches: {
    telemetry_enabled: { value: true, set: true, revision: 7 },
    commanding_enabled: { value: false, set: false, revision: null },
  },
  ...o,
});
