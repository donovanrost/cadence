import { describe, expect, it } from "vite-plus/test";
import { supersedeSentence } from "./supersedes.ts";

describe("supersede sentence (ux ContactPlanning.md)", () => {
  const draft = (day: string, id: string | null, name: string) => ({
    plan: { id: `p-${day}`, version: 1 },
    day,
    author: { id, name },
    state: "draft" as const,
  });
  it("lists day, revision and author, with 'you' for the reader", () => {
    expect(
      supersedeSentence(
        [draft("2026-11-11", "u1", "Mira K."), draft("2026-11-12", "me", "Me")],
        3,
        "me",
      ),
    ).toBe(
      "Saving v3 supersedes 2 open drafts: Wed 11 Nov (r1, Mira K.), Thu 12 Nov (r1, you). They'll need drafting again.",
    );
  });
  it("says one draft in the singular", () => {
    expect(supersedeSentence([draft("2026-11-15", "u2", "QA Operator")], 7, "me")).toBe(
      "Saving v7 supersedes 1 open draft: Sun 15 Nov (r1, QA Operator). It'll need drafting again.",
    );
  });
});
