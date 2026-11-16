import { describe, expect, it } from "vite-plus/test";
import { decode, type Actor } from "@/api";
import {
  failureOutcome,
  groupedLines,
  itemLine,
  previewReader,
  type PreviewItem,
} from "./actions.ts";

const base: PreviewItem = {
  op_id: null,
  change_id: null,
  kind: "transport",
  entity_id: null,
  reason: undefined,
  errors: undefined,
  spacecraft_count: undefined,
  profile_value: undefined,
  transport_value: undefined,
  sentence: undefined,
  detail: undefined,
  cause: undefined,
  entity_name: undefined,
  paths: undefined,
  spacecraft_ids: undefined,
  from: undefined,
  to: undefined,
  requests: undefined,
  blocking: undefined,
  details: null,
};

describe("preview compatibility HOLD (DECISIONS #33)", () => {
  it("decodes a framing mismatch and names both values", () => {
    const result = decode(previewReader, {
      verdict: "hold",
      checks: [
        {
          key: "compatibility",
          verdict: "hold",
          items: [
            {
              op_id: "o1",
              change_id: "c1",
              kind: "spacecraft_profile",
              entity_id: "p1",
              reason: "framing_mismatch",
              spacecraft_count: 499,
              profile_value: { path: "frame_parameters.frame_size", value: 1279 },
              transport_value: {
                transport: { id: "t1", name: "Svalbard X-band" },
                path: "configuration.framing.fixed_message_bytes",
                value: 1115,
              },
              sentence: "Frames won't decode until the transport matches.",
            },
          ],
        },
      ],
      effects: [],
    });
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const item = result.value.checks[0]?.items[0];
    if (!item) throw new Error("fixture");
    expect(itemLine(item)).toBe(
      "Frames won't decode until the transport matches. (profile frame_parameters.frame_size = 1279 vs Svalbard X-band configuration.framing.fixed_message_bytes = 1115 · 499 spacecraft)",
    );
  });

  it("renders framing_unverified with the profile side only (DECISIONS #40)", () => {
    expect(
      itemLine({
        ...base,
        reason: "framing_unverified",
        spacecraft_count: 3,
        profile_value: { path: "frame_parameters.frame_size", value: 1279 },
        sentence: "Can't verify against any transport.",
      }),
    ).toBe(
      "Can't verify against any transport. (profile frame_parameters.frame_size = 1279 · 3 spacecraft)",
    );
  });

  it("decodes framing_unverified with null values and shows the sentence", () => {
    const r = decode(previewReader, {
      verdict: "hold",
      checks: [
        {
          key: "compatibility",
          verdict: "hold",
          items: [
            {
              op_id: "o",
              change_id: "c",
              kind: "spacecraft_profile",
              entity_id: "p",
              reason: "framing_unverified",
              cause: "no_inbound_route",
              spacecraft_count: 12,
              profile_value: null,
              transport_value: null,
              sentence: "No inbound route to check against.",
            },
          ],
        },
      ],
      effects: [],
    });
    expect(r.ok).toBe(true);
    const item = r.ok ? r.value.checks[0]?.items[0] : undefined;
    if (!item) throw new Error("fixture");
    expect(itemLine(item)).toBe("No inbound route to check against.");
  });

  it("falls back to field errors, then the reason", () => {
    expect(itemLine({ ...base, errors: [{ path: "a", message: "bad" }] })).toBe("a: bad");
    expect(itemLine({ ...base, reason: { unrecognized: "entity_gone" } })).toBe("Entity gone");
  });
});

describe("failureOutcome", () => {
  it("names the field and the server's message for invalid_op (DECISIONS #36)", async () => {
    const { failureOutcome } = await import("./actions.ts");
    const outcome = failureOutcome(
      {
        kind: "invalid",
        code: "invalid_op",
        message: "A staged change is invalid.",
        details: {
          index: 0,
          errors: [
            {
              path: "catalog_revision_id",
              message: "Change catalogs through the spacecraft configuration review",
            },
          ],
        },
      },
      "staged",
    );
    expect(outcome).toEqual({
      changed: false,
      sentence:
        "Nothing was staged. catalog_revision_id: Change catalogs through the spacecraft configuration review",
    });
  });
});

describe("failureOutcome invalid_params", () => {
  it("names the fields from details (qa #21)", async () => {
    const { failureOutcome } = await import("./actions.ts");
    expect(
      failureOutcome(
        {
          kind: "invalid",
          code: "invalid_params",
          message: "The request parameters are invalid.",
          details: { comment: "is required" },
        },
        "changed",
      ).sentence,
    ).toBe("Nothing was changed. comment: is required");
  });
});

describe("conflict sentences (api 062a73f8, ux rollback review #1)", () => {
  const path = {
    path: "frame_parameters.frame_size",
    label: "frame size",
    unit: "bytes",
    format: null as string | null,
    base: 900,
    live: 1024,
    staged: 1115,
    changed_in: 9 as number | "outside",
    changed_by: { kind: "user" as const, id: null, name: "Mira K." } as Actor | null,
  };
  const item: PreviewItem = {
    ...base,
    kind: "spacecraft_profile",
    entity_id: "profile-earendil-block-1",
    entity_name: "Earendil Block 1",
    paths: [path],
  };
  it("names the field, both values, the revision and who changed it", () => {
    expect(itemLine(item, "r8")).toBe(
      "Earendil Block 1 · frame size is 1,024 bytes now, not 900 bytes as r8 left it (changed in r9 by Mira K.). Roll back r9 first, or change it by hand.",
    );
  });
  it("says outside changes without a name or a rollback hint", () => {
    const outside = {
      ...item,
      paths: [{ ...path, changed_in: "outside" as const, changed_by: null }],
    };
    expect(itemLine(outside, "r8")).toBe(
      "Earendil Block 1 · frame size is 1,024 bytes now, not 900 bytes as r8 left it (changed outside a change set). Change it by hand.",
    );
  });
});

describe("compatibility lines (ux rollback review #7, api 76a66307)", () => {
  const mismatch = (station: string): PreviewItem => ({
    ...base,
    kind: "spacecraft_profile",
    entity_id: "profile-earendil-block-1",
    entity_name: "Earendil Block 1 — Demo",
    reason: "framing_mismatch",
    spacecraft_count: 1,
    profile_value: { path: "frame_parameters.frame_size", value: 900 },
    transport_value: {
      transport: { id: `t-${station}`, name: `${station} (Demo) S-band downlink` },
      path: "ingress_metadata.frame_size",
      value: 1115,
    },
    sentence: `1 spacecraft on Earendil Block 1 — Demo would decode 900-byte frames, but ${station} (Demo) S-band downlink sends 1,115-byte frames.`,
    detail: `frame_parameters.frame_size = 900 (profile) vs ingress_metadata.frame_size = 1115 (${station})`,
  });
  it("folds transports that differ only by name into one line", () => {
    expect(groupedLines([mismatch("Santiago"), mismatch("Svalbard")])).toEqual([
      "1 spacecraft on Earendil Block 1 — Demo would decode 900-byte frames, but 2 transports send 1,115-byte frames (Santiago, Svalbard).",
    ]);
  });
  it("keeps a single mismatch as the server's sentence, without the raw detail", () => {
    expect(groupedLines([mismatch("Santiago")])).toEqual([
      "1 spacecraft on Earendil Block 1 — Demo would decode 900-byte frames, but Santiago (Demo) S-band downlink sends 1,115-byte frames.",
    ]);
  });
});

describe("version format (api 4721f61a)", () => {
  it("renders a version as v4 in conflict sentences", () => {
    const item: PreviewItem = {
      ...base,
      kind: "spacecraft",
      entity_name: "EARENDIL-001",
      paths: [
        {
          path: "spacecraft_type_version",
          label: "Profile version",
          unit: null,
          format: "version",
          base: 5,
          live: 6,
          staged: 4,
          changed_in: 9,
          changed_by: null,
        },
      ],
    };
    expect(itemLine(item, "r8")).toBe(
      "EARENDIL-001 · Profile version is v6 now, not v5 as r8 left it (changed in r9). Roll back r9 first, or change it by hand.",
    );
  });
});

describe("failureOutcome on 5xx (qa #19)", () => {
  it("says it's unclear and to check now, never that nothing changed", () => {
    const o = failureOutcome({ kind: "unavailable", status: 500, message: "boom" }, "applied");
    expect(o.changed).toBeNull();
    expect(o.sentence).toBe(
      "The server failed while answering, so it isn't clear whether anything was applied. Check Staged changes and Revisions now, before trying again.",
    );
  });
});

describe("#65 blocking holds", () => {
  it("reads blocking items as 'can't apply yet' with what clears them", async () => {
    const { blockingReason, rejectionSentence } = await import("./actions.ts");
    const preview = decode(previewReader, {
      verdict: "hold",
      checks: [
        {
          key: "compatibility",
          verdict: "hold",
          blocking: true,
          items: [
            {
              kind: "spacecraft",
              reason: "catalog_command_in_flight",
              sentence: "SET_MODE is radiating on EARENDIL-004.",
            },
          ],
        },
      ],
      effects: [],
    });
    if (!preview.ok) throw preview.error;
    expect(blockingReason(preview.value)).toBe(
      "Can't apply yet: SET_MODE is radiating on EARENDIL-004. Apply when those commands finish.",
    );
    expect(
      rejectionSentence({ kind: "conflict", code: "holds_blocking", message: "x", details: null }),
    ).toContain("It can't be acknowledged");
  });
});

describe("U63 apply refusals (api 396c59fd5)", () => {
  it("shows the server's sentence alone, without a second 'Nothing was applied'", () => {
    const message =
      "Not applied: the telemetry app isn't installed on EARENDIL-312. Install the app in Setup › Apps first.";
    expect(
      failureOutcome(
        {
          kind: "conflict",
          code: "telemetry_app_not_installed",
          message,
          details: { spacecraft_ids: ["sc_1"] },
        },
        "applied",
      ),
    ).toEqual({ changed: false, sentence: message });
    const inputs =
      "Not applied: telemetry can't be turned on for EARENDIL-312 until its packet inputs are set up.";
    expect(
      failureOutcome(
        {
          kind: "conflict",
          code: "telemetry_packet_inputs_required",
          message: inputs,
          details: null,
        },
        "applied",
      ).sentence,
    ).toBe(inputs);
  });
});

describe("U65 apply refusals (api 0d453d55f)", () => {
  it("shows the server's sentence; a failed comparison links to its report", () => {
    const notApproved = "Not applied: catalog rev 4 isn't approved yet.";
    expect(
      failureOutcome(
        {
          kind: "conflict",
          code: "mission_model_revision_not_approved",
          message: notApproved,
          details: { mission_model_revision_ids: ["mm-4"], catalog_revision_numbers: [4] },
        },
        "applied",
      ),
    ).toEqual({ changed: false, sentence: notApproved });
    const failed = "Not applied: catalog rev 4's comparison didn't pass.";
    expect(
      failureOutcome(
        {
          kind: "conflict",
          code: "mission_model_comparison_failed",
          message: failed,
          details: {
            mission_model_revision_id: "mm-4",
            comparison_report_id: "rep-1",
            catalog_revision_number: 4,
          },
        },
        "applied",
      ),
    ).toEqual({
      changed: false,
      sentence: failed,
      link: {
        label: "Open the report",
        to: { name: "setup.catalog.model", params: { revisionId: "mm-4" } },
      },
    });
  });
});

describe("fieldErrors (U79: an error sits on its field)", () => {
  const invalid = (index: number, errors: { path: string; message: string }[]) => ({
    kind: "invalid" as const,
    code: "invalid_op",
    message: "A staged change is invalid.",
    details: { index, errors },
  });
  it("puts each schema path's first message on its field and keeps the rest", async () => {
    const { fieldErrors } = await import("./actions.ts");
    const split = fieldErrors(
      invalid(0, [
        { path: "downlink", message: "Choose a role for downlink, uplink or both" },
        { path: "downlink", message: "a second one" },
        { path: "", message: "Each direction once" },
      ]),
      new Set(["downlink", "uplink"]),
    );
    expect(split).toEqual({
      onFields: { downlink: "Choose a role for downlink, uplink or both" },
      rest: [
        { path: "downlink", message: "a second one" },
        { path: "", message: "Each direction once" },
      ],
    });
  });
  it("leaves another op's errors and non-invalid_op failures alone", async () => {
    const { fieldErrors } = await import("./actions.ts");
    expect(
      fieldErrors(invalid(1, [{ path: "downlink", message: "x" }]), new Set(["downlink"])),
    ).toEqual({ onFields: {}, rest: [{ path: "downlink", message: "x" }] });
    expect(fieldErrors({ kind: "not_found", code: "x", message: "" }, new Set())).toBeNull();
  });
});
