import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api/index.ts";
import { eventsReader } from "./api.ts";
import { eventDetail } from "./eventDetail.ts";
import { craftLink, needsSpacecraftPrefix, rawKindLabel } from "./model.ts";

/** An events page as api serves it (ops.md `GET …/events`), decoded as the screen reads it. */
const page = (spacecraft: unknown) => {
  const r = decode(eventsReader, {
    from: "2026-11-14T00:00:00Z",
    to: "2026-11-15T00:00:00Z",
    events: [
      {
        id: "mission_event:9",
        at: "2026-11-14T04:12:00Z",
        kind: "contact",
        raw_kind: "contact_scid_mismatch",
        severity: "caution",
        text: "Most frames on the FBK 03:10Z pass carried another SCID",
        detail: "412 of 430 frames carried SCID 3, not this pass's SCID 1.",
        spacecraft,
        refs: {
          alarm_id: null,
          point_id: null,
          command_request_id: null,
          contact_id: "rc-9",
          subject: { kind: "contact", id: "rc-9", name: null },
        },
      },
    ],
  });
  if (!r.ok) throw new Error(r.error.message);
  return r.value.events;
};

describe("a Timeline event whose craft the server couldn't name (api 11-16)", () => {
  it("still decodes the page, shows no craft name and never the id", () => {
    const [e] = page({ id: "spacecraft-gone", name: null, scid: null });
    expect(e).toBeDefined();
    if (!e) return;
    expect(craftLink(e)).toBeNull();
    expect(needsSpacecraftPrefix(e)).toBe(false);
    const d = eventDetail(e);
    expect(d.links.map((l) => l.label)).not.toContain("spacecraft-gone");
    expect(d.links).toEqual([]);
  });

  it("a named craft links to its page", () => {
    const [e] = page({ id: "spacecraft-earendil-312", name: "EARENDIL-312", scid: 312 });
    if (!e) throw new Error("no event");
    expect(craftLink(e)).toEqual({
      label: "EARENDIL-312",
      to: { name: "ops.spacecraft", params: { scId: 312 } },
    });
    expect(needsSpacecraftPrefix(e)).toBe(true);
  });

  it("words the frame-SCID kind (ux U81 §2)", () => {
    expect(rawKindLabel("contact_scid_mismatch")).toBe("Frames with another SCID");
  });
});
