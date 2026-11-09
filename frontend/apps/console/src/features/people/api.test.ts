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

  it("rejects a role the console doesn't know", () => {
    const member = { ...body.members[0], role: "flight_director" };
    expect(decode(peopleReader, { ...body, members: [member] }).ok).toBe(false);
  });
});
