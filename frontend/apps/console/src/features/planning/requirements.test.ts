import { describe, expect, it } from "vite-plus/test";
import { missionId as missionIdReader, decode, spacecraftId } from "@/api";
import {
  endedLine,
  fetchRequirements,
  fieldErrors,
  notActiveLine,
  occurrenceDay,
  planningButton,
  planningDay,
  occurrenceScope,
  requirementFacts,
  withSpacecraftChoices,
  withoutBlankConstraints,
} from "./requirements.ts";
import { templateSchemaReader } from "./templates.ts";

const schema = decode(templateSchemaReader, {
  fields: [
    field("spacecraft_id", "Spacecraft", "reference", "window"),
    field("earliest_start", "Window opens", "datetime", "window"),
    field("latest_end", "Window closes", "datetime", "window"),
    field("contact_count", "Contacts", "integer", "requirement"),
    {
      ...field("max_gap_seconds", "Longest time without a contact", "integer", "requirement", true),
      unit: "s",
    },
  ],
  defaults: { contact_count: 1, max_gap_seconds: null },
});
function field(path: string, label: string, type: string, group: string, advanced = false) {
  return {
    path,
    label,
    type,
    unit: null,
    enum: null,
    range: null,
    default: null,
    required: false,
    help: null,
    visible_when: null,
    group,
    advanced,
  };
}
const byMira = {
  at: "2026-11-12T10:00:00Z",
  by: { kind: "user", id: "u1", name: "Mira K." },
  reason: "Pass met",
};

describe("one-off requirements (ux P4, api fb7510be)", () => {
  it("reads a list page, with or without rule_summary", async () => {
    const row = {
      id: "req_1",
      state: "closed",
      version: 2,
      spacecraft: { id: spacecraftId("sc1"), name: "EARENDIL-001", scid: null },
      template_id: null,
      content: { earliest_start: "2026-11-14T00:00:00Z", latest_end: "2026-11-15T00:00:00Z" },
      updated_at: "2026-11-12T10:00:00Z",
      state_changed: byMira,
    };
    const fetchMock = async () =>
      new Response(JSON.stringify({ data: { requirements: [row], page: 1, next_page: null } }), {
        status: 200,
      });
    const original = globalThis.fetch;
    globalThis.fetch = fetchMock as typeof fetch;
    try {
      const r = await fetchRequirements(
        { missionId: missionIdReader("m"), source: "one_off", page: 1 },
        new AbortController().signal,
      );
      expect(r.ok && r.value.requirements[0]?.rule_summary).toBeNull();
      expect(r.ok && endedLine(r.value.requirements[0] ?? (row as never))).toBe(
        "Closed by Mira K. on 11-12: Pass met",
      );
    } finally {
      globalThis.fetch = original;
    }
  });

  it("says who ended it from a 409, without a refetch", () => {
    expect(
      notActiveLine({
        kind: "conflict",
        code: "requirement_not_active",
        message: "x",
        details: { state: "canceled", state_changed: byMira },
      }),
    ).toBe("Already canceled by Mira K. on 11-12: Pass met.");
  });

  it("puts 422 details under their fields", () => {
    expect(
      fieldErrors({
        kind: "invalid",
        code: "invalid_params",
        message: "x",
        details: {
          max_gap_seconds: "must not be longer than the window",
          "content.foo": "unknown field",
        },
      }),
    ).toEqual({ max_gap_seconds: "must not be longer than the window", foo: "unknown field" });
  });

  it("offers spacecraft by name and reads an empty gap limit as 'No limit'", () => {
    if (!schema.ok) throw schema.error;
    const s = withSpacecraftChoices(schema.value, [{ id: "sc1", name: "EARENDIL-001" }]);
    expect(s.fields[0]?.enum).toEqual([{ value: "sc1", label: "EARENDIL-001" }]);
    const facts = requirementFacts(s, {
      spacecraft: { id: spacecraftId("sc1"), name: "EARENDIL-001", scid: null },
      content: { contact_count: 2, max_gap_seconds: null },
    });
    expect(facts.find((f) => f.key === "max_gap_seconds")?.value).toBe("No limit");
    expect(facts.find((f) => f.key === "contact_count")?.value).toBe("2");
    // ux U25 (#190): a nameless spacecraft reads Unknown spacecraft, never its id.
    const nameless = requirementFacts(s, {
      spacecraft: { id: spacecraftId("sc1"), name: null, scid: null },
      content: { contact_count: 2, max_gap_seconds: null },
    });
    expect(nameless.find((f) => f.key === "spacecraft")?.value).toBe("Unknown spacecraft");
  });
});

describe("From templates counts (api df98dcd3)", () => {
  it("reads 'Block 1 daily · 1,500 for 11-14 · 1,480 active'", async () => {
    const { templateCountLine } = await import("./requirements.ts");
    const row = {
      template: { id: "t1", name: "Block 1 daily", state: "active" as const },
      count: 1500,
      active_count: 1480,
    };
    expect(templateCountLine(row, "2026-11-14")).toBe("1,500 for 11-14 · 1,480 active");
    expect(templateCountLine({ ...row, active_count: 1500 }, "2026-11-14")).toBe("1,500 for 11-14");
    expect(
      templateCountLine({ ...row, template: { ...row.template, state: "paused" } }, "2026-11-14"),
    ).toBe("1,500 for 11-14 · 1,480 active · paused");
  });
});

describe("blank constraints (qa P4)", () => {
  it("leaves out an untouched constraints document, keeps a set one", () => {
    expect(
      withoutBlankConstraints({
        station_constraints_document: { allowed: null, excluded: null },
        provider_constraints_document: { allowed: ["p1"], excluded: null },
        max_gap_seconds: null,
      }),
    ).toEqual({
      provider_constraints_document: { allowed: ["p1"], excluded: null },
      max_gap_seconds: null,
    });
  });
});

describe("closing one template occurrence (ux, ContactPlanning.md)", () => {
  it("names the occurrence's day and template, and says when the template brings it back", () => {
    expect(occurrenceDay({ earliest_start: "2026-11-15T00:00:00Z" })).toBe("11-15");
    expect(occurrenceDay({})).toBeNull();
    expect(occurrenceScope("close", { day: "11-15", template: "Daily downlink" })).toEqual({
      lead: "This closes only the 11-15 occurrence of “Daily downlink”. The template's other days aren't affected.",
      final:
        "This is final for this day: the template won't bring it back, even when the template is edited. To plan 11-15 again, add a one-off requirement for it.",
    });
    expect(occurrenceScope("cancel", { day: "11-15", template: "Daily downlink" }).lead).toMatch(
      /^This cancels only the 11-15 occurrence/,
    );
  });
});

describe("planning a requirement (ux P4, whole-day planning)", () => {
  const now = Date.parse("2026-11-14T06:00:00Z");
  const row = (state: "active" | "closed" | "canceled", from: string, to: string) => ({
    state,
    content: { earliest_start: from, latest_end: to },
  });
  it("plans an active, unended window on its start's UTC day", () => {
    expect(planningDay(row("active", "2026-11-14T23:30:00Z", "2026-11-15T01:00:00Z"), now)).toEqual(
      {
        iso: "2026-11-14",
        md: "11-14",
        from: "2026-11-14T23:30:00Z",
        to: "2026-11-15T01:00:00Z",
      },
    );
  });
  it("plans a window that began on an earlier day on today, from now (ux: never a day that's over)", () => {
    expect(planningDay(row("active", "2026-11-13T12:00:00Z", "2026-11-15T00:00:00Z"), now)).toEqual(
      {
        iso: "2026-11-14",
        md: "11-14",
        from: "2026-11-14T06:00:00.000Z",
        to: "2026-11-15T00:00:00Z",
      },
    );
  });
  it("offers nothing once it's ended, closed or canceled, or without a window", () => {
    expect(
      planningDay(row("active", "2026-11-13T00:00:00Z", "2026-11-14T05:00:00Z"), now),
    ).toBeNull();
    expect(
      planningDay(row("closed", "2026-11-14T08:00:00Z", "2026-11-14T09:00:00Z"), now),
    ).toBeNull();
    expect(
      planningDay(row("canceled", "2026-11-14T08:00:00Z", "2026-11-14T09:00:00Z"), now),
    ).toBeNull();
    expect(planningDay({ state: "active", content: {} }, now)).toBeNull();
  });
});

describe("the requirement page's planning button (ux P4, api held_by)", () => {
  const now = Date.parse("2026-11-14T06:00:00Z");
  const base = {
    state: "active" as const,
    content: { earliest_start: "2026-11-15T08:00:00Z", latest_end: "2026-11-15T09:00:00Z" },
  };
  it("plans the day when nothing holds it, and opens the holding plan when one does", () => {
    expect(planningButton({ ...base, held_by: null }, now)).toEqual({
      label: "Plan 11-15",
      day: "2026-11-15",
    });
    expect(planningButton({ ...base, held_by: undefined }, now)).toEqual({
      label: "Plan 11-15",
      day: "2026-11-15",
    });
    expect(
      planningButton(
        {
          ...base,
          held_by: { plan_id: "p1", revision: 41, state: "approved", day: "2026-11-15" },
        },
        now,
      ),
    ).toEqual({ label: "Open plan R41", day: "2026-11-15" });
    expect(
      planningButton(
        { ...base, held_by: { plan_id: "p1", revision: 41, state: "executing", day: null } },
        now,
      ),
    ).toEqual({ label: "Open plan R41", day: "2026-11-15" });
  });
  it("shows nothing once the requirement can't be planned", () => {
    expect(
      planningButton(
        {
          ...base,
          state: "closed",
          held_by: { plan_id: "p1", revision: 2, state: "approved", day: undefined },
        },
        now,
      ),
    ).toBeNull();
  });
});
