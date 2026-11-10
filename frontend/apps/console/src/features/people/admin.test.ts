import { describe, expect, it } from "vite-plus/test";
import { accessGroups, adminErrorText } from "./admin.ts";

describe("adminErrorText (O5)", () => {
  it("explains last_admin and never claims a save on a dropped connection", () => {
    expect(
      adminErrorText({ kind: "conflict", code: "last_admin", message: "x", details: null }),
    ).toBe(
      "Nothing changed: the organization needs at least one admin. Make someone else an admin first.",
    );
    expect(adminErrorText({ kind: "unavailable", status: 0, message: "" })).toContain(
      "may or may not have changed",
    );
  });
});

describe("accessGroups", () => {
  it("groups known capabilities as sentences with YES/NO and keeps unknown tokens", () => {
    const groups = accessGroups(["command.request", "org.invite", "ops.future_thing"]);
    expect(groups.map((g) => g.group)).toEqual(["Command", "Approve", "Organization", "Other"]);
    expect(groups[0]?.lines).toEqual([
      { text: "Request commands", yes: true },
      { text: "Abort commands in flight", yes: false },
    ]);
    expect(groups[3]?.lines).toEqual([{ text: "ops.future_thing", yes: true }]);
  });
});
