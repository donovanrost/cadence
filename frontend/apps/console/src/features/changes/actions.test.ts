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

  it("falls back to field errors, then the reason", () => {
    expect(itemLine({ ...base, errors: [{ path: "a", message: "bad" }] })).toBe("a: bad");
    expect(itemLine({ ...base, reason: "entity_gone" })).toBe("entity_gone");
  });
});
