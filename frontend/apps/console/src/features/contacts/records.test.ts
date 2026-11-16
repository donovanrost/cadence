import { mount, RouterLinkStub } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api/index.ts";
import BookedRow from "./BookedRow.vue";
import { contactRecordReader, reservationReader } from "./records.ts";
import { sentenceCase, span, valueCells } from "./recordWords.ts";

const reservation = {
  reservation: {
    id: "res-1",
    provider_revision: 4,
    lifecycle_state: "confirmed",
    provider: { id: "nl", version: 4 },
    transport: null,
    plan: { id: "plan-1", version: 3 },
    requirement: null,
    scheduled_contact_id: "sc-1",
    last_reconciled_at: "2026-11-16T02:11:04Z",
  },
  values: [
    {
      field: "starts_at",
      requested_json: '"03:10"',
      confirmed_json: '"03:12"',
      accepted_json: '"03:10"',
      restricted: false,
      differs: true,
    },
    {
      field: "service_profile_ref",
      requested_json: null,
      confirmed_json: null,
      accepted_json: null,
      restricted: true,
      differs: false,
    },
  ],
  audit: { entries: [], next_cursor: null },
};

describe("pass records (ux U74, api A11/A13)", () => {
  it("decodes the reservation and words its value cells", () => {
    const r = decode(reservationReader, reservation);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    const [first, second] = r.value.values;
    if (!first || !second) throw new Error("fixture");
    const [req, conf, acc] = valueCells(first);
    expect([req.text, req.tone]).toEqual(["03:10", "base"]);
    expect([conf.text, conf.tone]).toEqual(["03:12", "differs"]);
    expect(acc.tone).toBe("same");
    const withheld = valueCells(second);
    expect(withheld[0]).toEqual({
      text: "Not shown",
      tone: "withheld",
      title: "Structured or over 512 bytes; Cadence doesn't display it.",
    });
  });
  it("says 'not set' for a missing value and sentence-cases codes", () => {
    const r = decode(reservationReader, reservation);
    const first = r.ok ? r.value.values[0] : undefined;
    if (!first) throw new Error("fixture");
    const cells = valueCells({ ...first, confirmed_json: null });
    expect(cells[1]).toEqual({ text: "not set", tone: "missing" });
    expect(sentenceCase("release_pending")).toBe("Release pending");
    expect(span("2026-11-16T02:59:40Z", "2026-11-16T03:08:52Z")).toBe("02:59:40–03:08:52Z");
  });
  it("decodes a contact record", () => {
    const r = decode(contactRecordReader, {
      subject: { id: "sc-1", kind: "scheduled" },
      scheduled: {
        id: "sc-1",
        current_revision: 3,
        lifecycle_state: "scheduled",
        starts_at: "2026-11-16T02:59:40Z",
        ends_at: "2026-11-16T03:08:52Z",
        realized_id: null,
        provider_contact_ref: null,
      },
      realized: null,
      paths: [],
      sources: [{ id: "src-1", side: "reviewed_schedule" }],
      intents: [],
      revisions: { entries: [], next_cursor: null },
      truncated: false,
    });
    expect(r.ok).toBe(true);
  });
  it("says where a plan booking came from, with both links", () => {
    const w = mount(BookedRow, {
      props: {
        pass: {
          plan: { id: "plan-1", version: 3, day: "2026-11-14" },
          requirement: { id: "req-1", version: 2, name: "Block 1 daily" },
        },
      },
      global: { stubs: { RouterLink: RouterLinkStub } },
    });
    expect(w.text().replace(/\s+/g, " ")).toBe(
      "Booked From the 11-14 plan (R3) · for Block 1 daily",
    );
    const links = w.findAllComponents(RouterLinkStub);
    expect(links[0]?.props("to")).toEqual({
      name: "ops.contacts.plan",
      query: { plan: "plan-1", day: "2026-11-14", version: "3" },
    });
    expect(links[1]?.props("to")).toMatchObject({ params: { requirementId: "req-1" } });
    const none = mount(BookedRow, {
      props: { pass: { plan: null, requirement: undefined } },
      global: { stubs: { RouterLink: RouterLinkStub } },
    });
    expect(none.text()).toBe("");
  });
});
