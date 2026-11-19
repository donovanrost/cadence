import { describe, expect, it } from "vite-plus/test";
import { passwordFailure, passwordProblems } from "./api.ts";

describe("passwordProblems", () => {
  it("checks length, sameness and confirmation before sending", () => {
    expect(passwordProblems("", "short", "x")).toEqual({
      current: "Enter your current password.",
      next: "Use at least 12 characters.",
      confirm: "The two new passwords don't match.",
    });
    expect(passwordProblems("same-password-1", "same-password-1", "same-password-1")).toEqual({
      next: "Choose a password different from the current one.",
    });
    expect(passwordProblems("old-password-1", "new-password-12", "new-password-12")).toEqual({});
  });
});

describe("passwordFailure", () => {
  it("puts a wrong current password inline and explains an externally managed one", () => {
    expect(
      passwordFailure({
        kind: "invalid",
        code: "current_password_incorrect",
        message: "x",
        details: null,
      }),
    ).toEqual({ text: null, fields: { current: "That isn't your current password." } });
    expect(
      passwordFailure({
        kind: "conflict",
        code: "password_managed_externally",
        message: "x",
        details: null,
      }).text,
    ).toContain("can't be changed here");
  });

  it("puts the server's new-password rule under the new password (422 invalid_params)", () => {
    expect(
      passwordFailure({
        kind: "invalid",
        code: "invalid_params",
        message: "x",
        details: { new_password: ["should be at least 12 character(s)"] },
      }),
    ).toEqual({ text: null, fields: { next: "should be at least 12 character(s)" } });
  });
});
