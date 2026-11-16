import { describe, expect, it } from "vite-plus/test";
import { scid, spacecraftId } from "@/api/index.ts";
import type { MissionEvent } from "./api.ts";
import { eventDetail, occurredText } from "./eventDetail.ts";

const baseRecord: NonNullable<MissionEvent["record"]> = {
  status: "canceled",
  source_record: { kind: "reservation", id: "res_1" },
  source_endpoint_ref: null,
  scheduled_contact_id: "sc_c1",
  realized_contact_id: null,
  path_id: "path_a",
  capability_instance_id: null,
  activation_id: null,
  correlation_key: "corr-1",
};

const event = (over: Partial<MissionEvent> = {}): MissionEvent => ({
  id: "mission_event:4812",
  at: "2026-11-15T02:51:03Z",
  kind: "contact",
  raw_kind: "contact_canceled",
  severity: "caution",
  text: "Contact canceled: KIR pass 02:31Z",
  detail: null,
  spacecraft: { id: spacecraftId("sc_312"), name: "EARENDIL-312", scid: scid(312) },
  refs: {
    alarm_id: null,
    point_id: null,
    command_request_id: "cr_77",
    contact_id: "ct_9",
    subject: { kind: "pass", id: "res_1", name: "KIR 02:31Z" },
  },
  record: baseRecord,
  ...over,
});

describe("Timeline event detail (ux U71 A8, api a87bee73d)", () => {
  it("lists the first-class fields in ux's order", () => {
    const d = eventDetail(event());
    expect(d.title).toBe("Contact canceled: KIR pass 02:31Z");
    expect(d.severity).toBe("Caution");
    expect(d.groupType).toMatch(/^Contacts · /);
    expect(d.occurred).toBe("Occurred 11-15 02:51:03Z");
    expect(d.links.map((l) => l.label)).toEqual(["EARENDIL-312", "KIR 02:31Z"]);
    expect(d.status).toBe("Canceled");
  });
  it("keeps ids, unnamed refs and a status code in Technical details", () => {
    const d = eventDetail(event({ record: { ...baseRecord, status: "E_409" } }));
    const labels = d.technical.map((t) => t.label);
    expect(labels).toEqual(
      expect.arrayContaining([
        "Event id",
        "Raw kind",
        "Status",
        "Source record",
        "Path",
        "Command request",
      ]),
    );
    expect(d.status).toBeNull();
    expect(d.technical.find((t) => t.label === "Source record")?.value).toBe("reservation res_1");
  });
  it("reads an older server's row without a record", () => {
    const d = eventDetail(event({ record: undefined }));
    expect(d.status).toBeNull();
    expect(d.technical[0]).toEqual({ label: "Event id", value: "mission_event:4812" });
  });
  it("words the occurrence with the date and seconds", () => {
    expect(occurredText("2026-01-02T03:04:05Z")).toBe("Occurred 01-02 03:04:05Z");
  });
});

describe("Timeline contact ids (U78)", () => {
  it("marks the scheduled and realized contact ids for History links", () => {
    const d = eventDetail(event({ record: { ...baseRecord, realized_contact_id: "rc_1" } }));
    expect(d.technical.filter((r) => r.contact).map((r) => [r.label, r.value])).toEqual([
      ["Scheduled contact", "sc_c1"],
      ["Realized contact", "rc_1"],
    ]);
  });
});
