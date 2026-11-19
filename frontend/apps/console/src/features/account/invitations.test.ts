import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api";
import { invitationFailure, invitationLine, myInvitationsReader } from "./invitations.ts";

describe("Account pending invitations (L21, api cfdf79f7)", () => {
  const body = {
    invitations: [
      {
        id: "inv_1",
        organization: { id: "o2", slug: "acme-space", name: "Acme Space" },
        role: "member",
        invited_by: { name: "Mira K." },
        invited_at: "2026-11-10T09:00:00Z",
        expires_at: null,
      },
    ],
  };
  it("reads a row as 'Acme Space · Member · invited by Mira K. on 11-10'", () => {
    const r = decode(myInvitationsReader, body);
    if (!r.ok) throw r.error;
    const i = r.value.invitations[0];
    if (!i) throw new Error("fixture");
    expect(invitationLine(i)).toBe("Acme Space · Member · invited by Mira K. on 11-10");
    expect(invitationLine({ ...i, role: "organization_admin", invited_by: null })).toBe(
      "Acme Space · Org admin · invited on 11-10",
    );
  });
  it("says why an invitation can't be answered", () => {
    expect(
      invitationFailure({ kind: "not_found", code: "invitation_not_found", message: "" }),
    ).toBe("This invitation isn't available any more.");
    expect(
      invitationFailure({
        kind: "conflict",
        code: "invitation_not_pending",
        message: "",
        details: { status: "revoked" },
      }),
    ).toBe("This invitation isn't pending any more. It was withdrawn by the organization.");
  });
});
