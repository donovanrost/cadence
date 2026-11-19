import { describe, expect, it } from "vite-plus/test";
import { invitationTag } from "./api.ts";

/** qa (api 510c85864): every status the org list returns reads as itself, never "Pending". */
describe("invitation status tags", () => {
  it("words each status", () => {
    expect(invitationTag("pending").label).toBe("Pending");
    expect(invitationTag("accepted")).toEqual({ state: "nominal", label: "Accepted" });
    expect(invitationTag("revoked").label).toBe("Withdrawn");
    expect(invitationTag("expired").label).toBe("Expired");
    expect(invitationTag("declined").label).toBe("Declined");
    expect(invitationTag({ unrecognized: "bounced" }).label).toBe("bounced");
  });
});
