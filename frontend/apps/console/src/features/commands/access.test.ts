import { describe, expect, it } from "vite-plus/test";
import { commandAccess } from "./access.ts";

describe("command access (DECISIONS #38)", () => {
  it("reads only the reported capabilities, never the role", () => {
    expect(commandAccess(new Set(["organization_admin"]))).toEqual({
      request: false,
      approve: false,
      abort: false,
    });
    expect(commandAccess(new Set(["command.request"]))).toEqual({
      request: true,
      approve: false,
      abort: false,
    });
    expect(commandAccess(new Set(["command.request", "command.approve", "command.abort"]))).toEqual(
      {
        request: true,
        approve: true,
        abort: true,
      },
    );
  });
});
