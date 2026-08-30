import { describe, expect, it } from "vite-plus/test";
import { filterPackets, type PacketBinding } from "./telemetry";

const packets: PacketBinding[] = [
  {
    apid: 100,
    name: "BUS HOUSEKEEPING",
    description: "Electrical power state",
    fieldCount: 18,
    rateHz: 1,
    selected: true,
  },
  {
    apid: 141,
    name: "PROPULSION",
    description: "Valve and tank pressure",
    fieldCount: 31,
    rateHz: 2,
    selected: false,
  },
];

describe("packet filtering", () => {
  it("matches APID, name, and description locally", () => {
    expect(filterPackets(packets, "141", false, new Set())).toEqual([packets[1]]);
    expect(filterPackets(packets, "house", false, new Set())).toEqual([packets[0]]);
    expect(filterPackets(packets, "pressure", false, new Set())).toEqual([packets[1]]);
  });

  it("uses the draft selection for selected-only filtering", () => {
    expect(filterPackets(packets, "", true, new Set([141]))).toEqual([packets[1]]);
  });
});
