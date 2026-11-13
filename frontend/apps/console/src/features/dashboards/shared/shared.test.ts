import { describe, expect, it } from "vite-plus/test";
import { endedShare } from "./api.ts";

describe("ended share links", () => {
  it("names a revoked or expired share and keeps the server's sentence", () => {
    expect(
      endedShare({
        kind: "not_found",
        code: "share_revoked",
        message: "Revoked by Mira K. at 11-14 02:10Z.",
      }),
    ).toEqual({
      kind: "revoked",
      message: "Revoked by Mira K. at 11-14 02:10Z.",
    });
    expect(endedShare({ kind: "not_found", code: "not_found", message: "" })).toBeNull();
    expect(endedShare({ kind: "forbidden", code: "forbidden", message: "" })).toBeNull();
  });
});
