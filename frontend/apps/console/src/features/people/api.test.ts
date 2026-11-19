import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api";
import { canApprove, canCommand, matchesPerson, peopleReader } from "./api.ts";

const body = {
  members: [
    {
      user_id: "u1",
      display_name: "Mira K.",
      email: "mira@example.com",
      role: "organization_admin",
      capabilities: ["command.request"],
      joined_at: null,
    },
  ],
  invitations: [],
  permissions: ["org.invite"],
};

describe("peopleReader", () => {
  it("decodes members and derives command rights from capabilities, not the role", () => {
    const result = decode(peopleReader, body);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const mira = result.value.members[0];
    if (!mira) throw new Error("fixture");
    expect(canCommand(mira)).toBe(true);
    expect(canApprove(mira)).toBe(false);
    expect(matchesPerson(mira, "org admin")).toBe(true);
  });

  it("reads a declined invitation (api-ops L5/L21)", () => {
    const invitation = {
      id: "inv_1",
      email: "ana@example.com",
      role: "member",
      invited_by: { name: "Mira K." },
      sent_at: "2026-11-10T01:00:00Z",
      expires_at: null,
      status: "declined",
    };
    const result = decode(peopleReader, { ...body, invitations: [invitation] });
    expect(result.ok && result.value.invitations[0]?.status).toBe("declined");
  });

  it("reads a role the console doesn't know as unrecognized, keeping its word (typing §12 A5)", async () => {
    const { roleText } = await import("@/api");
    const member = { ...body.members[0], role: "flight_director" };
    const r = decode(peopleReader, { ...body, members: [member] });
    if (!r.ok) throw r.error;
    const read = r.value.members[0];
    if (!read) throw new Error("fixture");
    expect(roleText(read.role)).toBe("flight_director");
  });
});
