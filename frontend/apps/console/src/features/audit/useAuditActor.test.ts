import { describe, expect, it } from "vite-plus/test";
import type { Member } from "@/features/people/index.ts";
import { actorOptions } from "./useAuditActor.ts";

const member = (user_id: string, display_name: string | null, email: string): Member => ({
  user_id,
  display_name,
  email,
  role: "member",
  capabilities: [],
  joined_at: null,
});

describe("audit actor options", () => {
  const members = [member("u2", "Mira K.", "mira@x"), member("u1", null, "ana@x")];
  it("lists everyone first, then members by name (email when there's no name)", () => {
    expect(actorOptions(members, null)).toEqual([
      { value: "", label: "Everyone" },
      { value: "u1", label: "ana@x" },
      { value: "u2", label: "Mira K." },
    ]);
  });
  it("keeps the queried actor when they aren't a member any more", () => {
    expect(actorOptions(members, { id: "u9", name: "Old Op" })[1]).toEqual({
      value: "u9",
      label: "Old Op",
    });
    expect(actorOptions(members, { id: "u2", name: "Mira K." })).toHaveLength(3);
  });
});
