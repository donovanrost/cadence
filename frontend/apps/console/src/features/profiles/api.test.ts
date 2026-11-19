import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api";
import { lastChangeText, manyOverrides, profilesReader, protocolLine } from "./api.ts";

const profile = (extra: Record<string, unknown> = {}) => ({
  id: "profile-1",
  name: "Earendil Block 1",
  version: 4,
  downlink_protocol: { value: "tm", label: "CCSDS TM" },
  uplink_protocol: { value: "tc", label: "CCSDS TC" },
  packet_protocol: { value: "space_packet", label: "CCSDS Space Packet" },
  catalog_revision: null,
  spacecraft_count: 500,
  spacecraft_on_older_versions: 3,
  ...extra,
});

describe("profilesReader", () => {
  it("decodes profiles with labelled protocol enums", () => {
    const result = decode(profilesReader, { profiles: [profile()] });
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.value[0]?.spacecraftOnOlderVersions).toBe(3);
    if (result.value[0]) expect(protocolLine(result.value[0])).toBe("CCSDS TM ↓ · CCSDS TC ↑");
  });

  it("rejects more spacecraft on older versions than in total", () => {
    expect(
      decode(profilesReader, { profiles: [profile({ spacecraft_on_older_versions: 501 })] }).ok,
    ).toBe(false);
  });

  it("rejects a protocol without a label", () => {
    expect(
      decode(profilesReader, { profiles: [profile({ uplink_protocol: { value: "tc" } })] }).ok,
    ).toBe(false);
  });

  it("reads Overrides and Last changed when sent, null when not (Profile.md list)", () => {
    const old = decode(profilesReader, { profiles: [profile()] });
    expect(old.ok && old.value[0]?.overrideCount).toBeNull();
    const r = decode(profilesReader, {
      profiles: [
        profile({
          override_count: 60,
          last_change: { version: 4, revision: 5, at: "2026-10-19T02:29:00Z", actor: null },
        }),
      ],
    });
    if (!r.ok) throw r.error;
    const row = r.value[0];
    if (!row?.lastChange) throw new Error("fixture");
    expect(lastChangeText(row.lastChange)).toBe("r5");
    expect(lastChangeText({ ...row.lastChange, revision: null })).toMatch(/^v4 · 10-19 02:29Z$/);
    expect(manyOverrides(row)).toBe(true);
    expect(manyOverrides({ ...row, overrideCount: 50 })).toBe(false);
  });
});
