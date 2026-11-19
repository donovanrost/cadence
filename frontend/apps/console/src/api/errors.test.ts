import { describe, expect, it } from "vite-plus/test";
import { object, string } from "./decode.ts";
import { codeOf, detailsOf, fieldErrors, isError } from "./errors.ts";
import type { ApiError } from "./http.ts";

const invalid = (code: string, details: unknown): ApiError => ({
  kind: "invalid",
  code,
  message: "x",
  details,
});

describe("typed error codes (§12 A2)", () => {
  it("matches a refusal or a 5xx envelope by its code", () => {
    const conflict: ApiError = {
      kind: "conflict",
      code: "version_conflict",
      message: "x",
      details: {},
    };
    expect(isError(conflict, "version_conflict")).toBe(true);
    expect(isError(conflict, "plan_superseded")).toBe(false);
    const down: ApiError = {
      kind: "unavailable",
      status: 503,
      message: "x",
      serverCode: "apply_interrupted",
    };
    expect(isError(down, "apply_interrupted")).toBe(true);
    expect(codeOf({ kind: "unauthenticated" })).toBeNull();
    expect(isError(null, "version_conflict")).toBe(false);
    // @ts-expect-error a misspelled code is a compile error, not a silently missed recovery path
    isError(conflict, "version_conlfict");
  });

  it("decodes details with a reader, and reads field errors once for every form", () => {
    const e = invalid("invitation_unavailable", { case: "expired" });
    expect(detailsOf(e, object({ case: string }))).toEqual({ case: "expired" });
    expect(detailsOf(e, object({ other: string }))).toBeNull();
    const form = invalid("invalid_params", {
      "settings.name": ["is required", "too short"],
      code: "taken",
      ignored: 3,
    });
    expect(fieldErrors(form, (p) => p.replace(/^settings\./, ""))).toEqual({
      name: "is required too short",
      code: "taken",
    });
    expect(fieldErrors({ kind: "unauthenticated" })).toEqual({});
  });
});
