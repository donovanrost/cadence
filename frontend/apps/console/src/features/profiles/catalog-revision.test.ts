import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api";
import { catalogRevText } from "./api.ts";
import { profileDetailReader } from "./detail.ts";
import { profileSubline } from "./present.ts";

/** A profile detail as the read sends it, with the given catalog_revision (#247). */
function detail(catalogRevision: unknown) {
  const r = decode(profileDetailReader, {
    profile: {
      id: "type_1",
      name: "Earendil Block 1",
      version: 4,
      catalog_revision: catalogRevision,
      protocols: {
        downlink: { value: "tm", label: "CCSDS TM" },
        uplink: { value: "tc", label: "CCSDS TC" },
        packet: { value: "space_packet", label: "CCSDS Space Packet" },
      },
      last_change: null,
    },
    inherit_count: 500,
    on_older_versions: 0,
    override_count: 0,
    sections: [],
    applications: null,
    rules: [],
    overrides: [],
    routing_model: "per_spacecraft",
    versions: [],
  });
  if (!r.ok) throw new Error(JSON.stringify(r.error));
  return r.value;
}

describe("a profile's catalog revision (#247)", () => {
  it("reads an unnumbered revision (id only, or number null) as U65's 'a catalog revision'", () => {
    const d = detail({ id: "catalog_revision_1" });
    expect(d.profile.catalog_revision).toEqual({
      id: "catalog_revision_1",
      number: null,
      label: null,
    });
    expect(profileSubline(d)).toContain("· a catalog revision");
    const nulled = detail({ id: "catalog_revision_9", number: null, label: null });
    expect(profileSubline(nulled)).toContain("· a catalog revision");
  });
  it("names the revision when the server numbers it, as setup.md says", () => {
    const d = detail({ id: "catalog_revision_1", number: 4, label: "rev 4" });
    expect(profileSubline(d)).toContain("catalog rev 4");
    expect(d.profile.catalog_revision && catalogRevText(d.profile.catalog_revision)).toBe("rev 4");
  });
  it("still says set per spacecraft when the profile sets none", () => {
    expect(profileSubline(detail(null))).toContain("catalog set per spacecraft");
  });
});
