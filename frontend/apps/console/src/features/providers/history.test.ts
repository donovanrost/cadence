import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api";
import { changeLines, versionsReader } from "./history.ts";

describe("provider account history (PA1)", () => {
  it("reads versions and words each change; v1 reads Created", () => {
    const r = decode(versionsReader, {
      id: "pa_1",
      name: "Northlight",
      current_version: 2,
      versions: [
        {
          version: 2,
          created_at: "2026-11-10T05:17:00Z",
          actor: { kind: "user", id: "u1", name: "Mira K." },
          changes: [
            { field: "credential.key", label: "Reference", before: "NL_KEY", after: "NL_KEY_2" },
            { field: "settings.region", label: null, before: null, after: "eu" },
          ],
        },
        { version: 1, created_at: "2026-11-09T05:17:00Z", actor: null, changes: [] },
      ],
    });
    if (!r.ok) throw r.error;
    const [v2, v1] = r.value.versions;
    if (!v2 || !v1) throw new Error("missing versions");
    expect(changeLines(v2, false)).toEqual([
      "Reference: NL_KEY → NL_KEY_2",
      "settings.region: — → eu",
    ]);
    expect(changeLines(v1, true)).toEqual(["Created."]);
  });
});
