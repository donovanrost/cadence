import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api/index.ts";
import { targetEndpointsReader } from "../groups/api.ts";
import EndpointCell from "./EndpointCell.vue";
import SubmitOutcome from "./SubmitOutcome.vue";

/** Typing §12B (commands): refusals and failures read from typed vocabularies, not text. */
const endpoints = (failure: string | null) => {
  const r = decode(targetEndpointsReader, {
    spacecraft_id: "sc-1",
    resolved_source_endpoint_id: null,
    failure,
    routes: [],
    endpoints: [],
  });
  if (!r.ok) throw new Error(r.error.message);
  return r.value;
};
const cell = (failure: string | null) =>
  mount(EndpointCell, {
    props: { name: "EARENDIL-001", info: endpoints(failure), override: undefined, via: null },
  }).text();

describe("why a target has no uplink endpoint (commanding.md)", () => {
  it("words the contract's failures", () => {
    expect(cell("no_uplink_route")).toContain("No uplink route");
    expect(cell("multiple_primary_uplink_routes")).toContain("Several primary uplink routes");
  });
  it("falls back for none or a code the console doesn't know", () => {
    expect(cell(null)).toContain("No uplink endpoint");
    expect(cell("routing_table_missing")).toContain("No uplink endpoint");
  });
});

describe("a rejected submit", () => {
  it("offers the re-check line only when the preflight went stale", () => {
    const text = (stale: boolean) =>
      mount(SubmitOutcome, {
        props: { state: { status: "rejected", stale, message: "x" } },
      }).text();
    expect(text(true)).toContain("The checks ran again");
    expect(text(false)).not.toContain("The checks ran again");
  });
});
