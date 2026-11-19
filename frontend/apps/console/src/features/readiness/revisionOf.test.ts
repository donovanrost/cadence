import { describe, expect, it } from "vite-plus/test";
import { compareSpan, revisionOf } from "./revisionOf.ts";

describe("R2 compare link", () => {
  it("spans the revisions shown, from the one before the oldest", () => {
    expect(compareSpan(["r6", "v4", "r5", "r3"])).toEqual({ from: "2", to: "6" });
    expect(compareSpan(["r2", "r1"])).toEqual({ from: "1", to: "2" });
  });
  it("needs two change-set revisions", () => {
    expect(compareSpan(["r6", "app", null])).toBeNull();
    expect(revisionOf("v4")).toBeNull();
  });
});
