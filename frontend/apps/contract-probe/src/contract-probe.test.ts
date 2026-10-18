import { describe, expect, it } from "vite-plus/test";
import { manifest } from "./federated-application";

describe("Contract Probe federated application", () => {
  it("contributes a second host-approved application identity", () => {
    expect(manifest.application.applicationKey).toBe("contract_probe");
    expect(manifest.surfaces[0]?.dataContract.id).toBe("cadence.contract_probe.snapshot");
  });
});
