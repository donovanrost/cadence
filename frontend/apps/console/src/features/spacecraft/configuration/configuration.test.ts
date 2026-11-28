import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api/index.ts";
import { packetChoicesReader, snapshotReader, submitResultReader } from "./api.ts";
import { snapshotWire } from "./fixtures.ts";

/** (B) readers first (api's shape diff, ux U94). */
describe("the configuration workspace snapshot", () => {
  it("reads api's shape: the draft, the active entry, approval and the switches", () => {
    const r = decode(snapshotReader, snapshotWire());
    if (!r.ok) throw r.error;
    expect(r.value.saved_version).toBe(4);
    expect(r.value.active?.version).toBe(3);
    expect(r.value.document.handled_apids).toEqual([42, 43]);
    expect(r.value.approval.requirement).toBe("independent");
    expect(r.value.switches.telemetry_enabled).toEqual({
      value: true,
      set: true,
      revision: 7,
    });
  });

  it("reads who may save a draft from the server's own check, can_save (#1160 row 2)", () => {
    // can_save is :operate_mission, the check a draft save makes; can_request is a different one.
    const approval = (o: Record<string, unknown>) => ({
      ...snapshotWire().approval,
      ...o,
    });
    const read = (a: unknown) => decode(snapshotReader, snapshotWire({ approval: a }));
    const operator = read(approval({ can_request: false, can_save: true }));
    if (!operator.ok) throw operator.error;
    expect(operator.value.approval.can_save).toBe(true);
    const { can_save: _dropped, ...older } = approval({});
    expect(read(older).ok).toBe(false);
  });

  it("reads a craft that was never set up and never saved", () => {
    const r = decode(snapshotReader, snapshotWire({ active: null, saved_version: null }));
    if (!r.ok) throw r.error;
    expect(r.value.active).toBeNull();
    expect(r.value.saved_version).toBeNull();
  });

  it("switches come only from switches: the document carries none (#109, api)", () => {
    const r = decode(snapshotReader, snapshotWire());
    if (!r.ok) throw r.error;
    expect("telemetry_enabled" in r.value.document).toBe(false);
    // Without the switches block the read fails: it's their only source.
    expect(decode(snapshotReader, { ...snapshotWire(), switches: undefined }).ok).toBe(false);
  });

  it("an unknown review state or framing keeps its raw word instead of failing the read", () => {
    const r = decode(
      snapshotReader,
      snapshotWire({
        review: { id: "rq-1", state: "paused", requester_id: "u-1", version: 4 },
      }),
    );
    if (!r.ok) throw r.error;
    expect(r.value.review?.state).toEqual({ unrecognized: "paused" });
  });

  it("reads the packet choices and the submit answers", () => {
    expect(
      decode(packetChoicesReader, {
        catalog_id: "cr-14",
        packets: [{ apid: 42, name: "HK", definitions: 12 }],
      }).ok,
    ).toBe(true);
    const sent = decode(submitResultReader, { state: "approval_pending", request_id: "rq-9" });
    expect(sent.ok && sent.value).toEqual({ state: "approval_pending", request_id: "rq-9" });
    expect(decode(submitResultReader, { state: "needs_review" }).ok).toBe(true);
  });
});
