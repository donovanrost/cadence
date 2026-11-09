import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api";
import { itemLine, previewReader, type PreviewItem } from "./actions.ts";

const base: PreviewItem = {
  op_id: null,
  change_id: null,
  kind: "x",
  entity_id: null,
  reason: undefined,
  errors: undefined,
  spacecraft_count: undefined,
  profile_value: undefined,
  transport_value: undefined,
  sentence: undefined,
  cause: undefined,
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
    expect(itemLine({ ...base, reason: "entity_gone" })).toBe("Entity gone");
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
