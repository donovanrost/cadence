import { describe, expect, it } from "vite-plus/test";
import { commandAccess } from "./access.ts";

describe("command access (DECISIONS #38)", () => {
  it("reads only the reported capabilities, never the role", () => {
    expect(commandAccess(new Set(["organization_admin"]))).toEqual({
      request: false,
      approve: false,
    });
    expect(commandAccess(new Set(["command.request"]))).toEqual({
      request: true,
      approve: false,
    });
    expect(commandAccess(new Set(["command.request", "command.approve"]))).toEqual({
      request: true,
      approve: true,
    });
  });
});
