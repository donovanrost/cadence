import { describe, expect, it } from "vite-plus/test";

import activationSource from "./OpsActivationRequests.vue?raw";
import commandsSource from "./OpsCommands.vue?raw";
import dataOperationsSource from "./OpsDataOperations.vue?raw";
import telemetrySource from "./OpsTelemetryExplore.vue?raw";

describe("mission operations cohort bindings", () => {
  it("keeps activation review local while retaining the real decision event", () => {
    expect(activationSource).toContain("@cadence/plugin-host/capability-management");
    expect(activationSource).toContain("export default OpsActivationRequests");
    expect(activationSource).not.toContain("<template>");
  });

  it("delegates commands to the domain module's public feature entry", () => {
    expect(commandsSource).toContain("@cadence/commanding/mission-commands");
    expect(commandsSource).toContain("export default OpsCommands");
    expect(commandsSource).not.toContain("<template>");
  });

  it("delegates legacy Explore to the module's canonical-page adapter", () => {
    expect(telemetrySource).toContain("@cadence/dashboards-and-exploration/exploration");
    expect(telemetrySource).toContain("export default ExplorationLegacyRedirect");
    expect(telemetrySource).not.toContain("<template>");
  });

  it("delegates historical workflows to the data-operations feature owner", () => {
    expect(dataOperationsSource).toContain("@cadence/data-operations/historical-workflows");
    expect(dataOperationsSource).toContain("export default OpsDataOperations");
    expect(dataOperationsSource).not.toContain("<template>");
  });
});
