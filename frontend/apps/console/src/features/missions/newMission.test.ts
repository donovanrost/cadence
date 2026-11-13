import { describe, expect, it } from "vite-plus/test";
import type { ApiError } from "@/api";
import { blockedReason, createFailure, takenLine } from "./newMission.ts";

/** Fixtures: plans/mission-create.md M1/M2 (api agreed 11-13; 422 details flat, as AD1). */
const invalid = (details: unknown): ApiError => ({
  kind: "invalid",
  code: "invalid_params",
  message: "Invalid parameters.",
  details,
});

describe("mission create (L4)", () => {
  it("says a taken slug with the free one", () => {
    expect(takenLine({ slug: "earendil", available: false, suggestion: "earendil-2" })).toBe(
      "earendil is taken; earendil-2 is free.",
    );
    expect(takenLine({ slug: "earendil", available: false, suggestion: null })).toBe(
      "earendil is taken.",
    );
    expect(takenLine({ slug: "earendil", available: true, suggestion: null })).toBeNull();
    expect(takenLine(null)).toBeNull();
  });

  it("explains why Create mission is off", () => {
    const base = { name: "Earendil", slug: "earendil", taken: null, busy: false };
    expect(blockedReason({ ...base, name: "  " })).toBe("Name the mission first.");
    expect(blockedReason({ ...base, slug: "" })).toBe("Give it a slug.");
    expect(blockedReason({ ...base, taken: "earendil is taken." })).toBe("Choose another slug.");
    expect(blockedReason({ ...base, busy: true })).toBe("Creating…");
    expect(blockedReason(base)).toBeNull();
  });

  it("puts a 422 on the fields, with the suggestion on the slug", () => {
    expect(
      createFailure(invalid({ slug: "This slug is already in use.", suggestion: "earendil-2" })),
    ).toEqual({ name: null, slug: "This slug is already in use. earendil-2 is free.", text: null });
    expect(createFailure(invalid({ name: ["Enter a value."] }))).toEqual({
      name: "Enter a value.",
      slug: null,
      text: null,
    });
  });

  it("says who may create on a 403", () => {
    const forbidden: ApiError = { kind: "forbidden", code: "forbidden", message: "Forbidden." };
    expect(createFailure(forbidden).text).toBe("Only organization admins can create missions.");
  });
});
