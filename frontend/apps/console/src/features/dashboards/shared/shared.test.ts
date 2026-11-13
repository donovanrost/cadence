import { describe, expect, it } from "vite-plus/test";
import { endedLink } from "./api.ts";

describe("ended links", () => {
  it("names a revoked or expired share and keeps the server's sentence", () => {
    expect(
      endedLink({
        kind: "not_found",
        code: "share_revoked",
        message: "Revoked by Mira K. at 11-14 02:10Z.",
      }),
    ).toEqual({
      kind: "revoked",
      message: "Revoked by Mira K. at 11-14 02:10Z.",
    });
    expect(endedLink({ kind: "not_found", code: "not_found", message: "" })).toBeNull();
    expect(endedLink({ kind: "forbidden", code: "forbidden", message: "" })).toBeNull();
  });

  it("names a deleted snapshot (404 snapshot_deleted, api f622f0772)", () => {
    expect(
      endedLink({
        kind: "not_found",
        code: "snapshot_deleted",
        message: "Deleted by Mira K. on 11-14.",
      }),
    ).toEqual({ kind: "deleted", message: "Deleted by Mira K. on 11-14." });
  });
});
