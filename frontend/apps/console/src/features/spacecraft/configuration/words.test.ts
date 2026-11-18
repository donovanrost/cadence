import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api/index.ts";
import { snapshotReader } from "./api.ts";
import ComparisonTable from "./ComparisonTable.vue";
import { documentWire, snapshotWire } from "./fixtures.ts";
import SetupSteps from "./SetupSteps.vue";
import SwitchesPanel from "./SwitchesPanel.vue";
import {
  apidsWord,
  catalogWord,
  changesCount,
  changesFromLine,
  comparisonRows,
  framingWord,
  notSetUpLine,
  readRefusal,
  setupSteps,
  statusTag,
  switchLine,
  versionsLine,
} from "./words.ts";

const read = (o: Record<string, unknown> = {}) => {
  const r = decode(snapshotReader, snapshotWire(o));
  if (!r.ok) throw r.error;
  return r.value;
};
const stubs = { RouterLink: { props: ["to"], template: "<a :data-to='to.name'><slot /></a>" } };

/** ux U94: the workspace's words (read side). */
describe("U94 status, steps and fields", () => {
  it("tags carry the state only; versions go in the header line (U94 (b))", () => {
    expect(statusTag(read())).toEqual({ label: "Draft saved", state: "caution" });
    expect(versionsLine(read())).toBe("v3 active · v4 saved");
    const same = read({ document: documentWire({ handled_apids: [42] }) });
    expect(statusTag(same)).toEqual({ label: "Active", state: "nominal" });
    expect(versionsLine(same)).toBe("v3 active");
    const fresh = read({ active: null, saved_version: null });
    expect(statusTag(fresh)).toEqual({ label: "Not set up", state: "off" });
    expect(versionsLine(fresh)).toBeNull();
    expect(versionsLine(read({ active: null }))).toBe("v4 saved");
    const v0 = read({
      saved_version: null,
      active: { version: 0, generation: 1, document: documentWire() },
    });
    expect(versionsLine(v0)).toBeNull();
  });

  it("reads the snapshot's refusals as a state", () => {
    expect(readRefusal("spacecraft_not_found")?.text).toBe(
      "This spacecraft isn't on this mission.",
    );
    expect(readRefusal("spacecraft_source_limit_exceeded")?.comms).toBe(true);
    expect(readRefusal("forbidden")?.text).toBe(
      "You can't change this spacecraft's configuration.",
    );
    expect(readRefusal("http_500")).toBeNull();
  });

  it("lists the steps left, in U94's words", () => {
    const doc = read({
      document: documentWire({ catalog_revision_id: null, handled_apids: [] }),
    }).document;
    const steps = setupSteps(doc, "EARENDIL-004", true);
    // Telemetry off: nothing to decode, so no decode step (#109: the switch, not the document).
    expect(setupSteps(doc, "EARENDIL-004", false).map((s) => s.key)).toEqual(["catalog"]);
    expect(steps.map((s) => s.label)).toEqual([
      "Choose a catalog revision",
      "Choose what to decode",
    ]);
    expect(steps[0]?.detail).toBe(
      "Pick the catalog revision that matches EARENDIL-004's flight software.",
    );
  });

  it("names catalogs as catalog rev N, APIDs in hex, framing in protocol terms", () => {
    const s = read({
      catalogs: [
        {
          id: "cr-14",
          name: "EARENDIL FSW",
          label: "FSW 2.4",
          declarations: 1,
          packets: 1,
          commands: 1,
          number: 14,
        },
      ],
    });
    expect(catalogWord(s, "cr-14")).toBe("catalog rev 14");
    expect(catalogWord(read(), "cr-14")).toBe("EARENDIL FSW · catalog rev 14");
    expect(catalogWord(s, null)).toBe("No catalog revision");
    expect(apidsWord([42, 43])).toBe("0x2A, 0x2B");
    expect(framingWord(s.document.protocol)).toBe("TM ↓ / TC ↑ · 1,115 B frames · headers 0/0/4 B");
  });
});

describe("U94 switches (DECISIONS #109)", () => {
  it("reads set by rN, set through Changes, or never set", () => {
    expect(switchLine({ value: true, set: true, revision: 7 }, "EARENDIL-004")).toBe(
      "On · set by r7.",
    );
    expect(switchLine({ value: false, set: true, revision: null }, "EARENDIL-004")).toBe(
      "Off · set through Setup › Changes.",
    );
    expect(switchLine({ value: false, set: false, revision: null }, "EARENDIL-004")).toBe(
      "Off · no change set has turned it on yet. Turn it on in EARENDIL-004's Operation panel; it applies with the next change set.",
    );
  });

  it("shows both read-only, each with Open Operation to the craft's page", () => {
    const w = mount(SwitchesPanel, { props: { snapshot: read() }, global: { stubs } });
    expect(w.text()).toContain("TelemetryOn · set by r7.");
    expect(w.findAll("a").map((a) => a.attributes("data-to"))).toEqual([
      "setup.spacecraft.one",
      "setup.spacecraft.one",
    ]);
    expect(w.find("input").exists()).toBe(false);
  });
});

describe("U94 pointers to Changes", () => {
  it("counts the differences on the tab and says them on the Overview", () => {
    expect(changesCount(read())).toBe(1);
    expect(changesFromLine(read())).toBe("1 change from v3");
    const same = read({ document: documentWire({ handled_apids: [42] }) });
    expect(changesCount(same)).toBeUndefined();
    expect(changesFromLine(same)).toBeNull();
    expect(changesCount(read({ active: null }))).toBe(4);
    expect(notSetUpLine("EARENDIL-004", true)).toBe(
      "Nothing runs for EARENDIL-004 until its configuration is activated.",
    );
  });
});

describe("U94 comparison", () => {
  it("shows only changed settings, never the switches", () => {
    expect(comparisonRows(read())).toEqual([
      { setting: "Handled APIDs", active: "0x2A", draft: "0x2A, 0x2B", mono: true },
    ]);
    const switched = read({
      document: documentWire({ handled_apids: [42] }),
      switches: {
        telemetry_enabled: { value: true, set: true, revision: 7 },
        commanding_enabled: { value: true, set: true, revision: 8 },
      },
    });
    expect(comparisonRows(switched)).toEqual([]);
  });

  it("nothing active: every setting, no Active column, and U90's line", () => {
    const w = mount(ComparisonTable, {
      props: { snapshot: read({ active: null }) },
      global: { stubs },
    });
    expect(w.text()).toContain("Nothing is active yet, so every setting is new.");
    expect(w.findAll("tbody tr")).toHaveLength(4);
    // U94: a first start drops the Active column instead of a column of dashes.
    expect(w.findAll("th").map((t) => t.text())).toEqual(["Setting", "Draft"]);
    expect(w.text()).not.toContain("—");
  });

  it("no changes: the draft matches", () => {
    const w = mount(ComparisonTable, {
      props: { snapshot: read({ document: documentWire({ handled_apids: [42] }) }) },
      global: { stubs },
    });
    expect(w.text()).toContain("The draft matches the active configuration.");
  });

  it("not set up: the info line and the steps link to Catalog & applications", () => {
    const w = mount(SetupSteps, {
      props: {
        snapshot: read({
          active: null,
          document: documentWire({ catalog_revision_id: null }),
          switches: {
            telemetry_enabled: { value: false, set: false, revision: null },
            commanding_enabled: { value: false, set: false, revision: null },
          },
        }),
      },
      global: { stubs },
    });
    expect(w.text()).toContain(
      "Nothing runs for EARENDIL-004 until its configuration is activated, and nothing is decoded until a change set turns telemetry on.",
    );
    expect(w.find("ol").exists()).toBe(true);
    expect(w.find("a").text()).toBe("Choose a catalog revision");
  });
});
