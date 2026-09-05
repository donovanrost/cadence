import { describe, expect, it } from "vite-plus/test";

import activationSource from "./OpsActivationRequests.vue?raw";
import commandsSource from "./OpsCommands.vue?raw";
import dataOperationsSource from "./OpsDataOperations.vue?raw";
import telemetrySource from "./OpsTelemetryExplore.vue?raw";

describe("mission operations cohort bindings", () => {
  it("keeps activation review local while retaining the real decision event", () => {
    expect(activationSource).not.toContain('review: [payload:');
    expect(activationSource).toContain('emit("decide"');
    expect(activationSource).toContain("const selectedRequest = ref");
  });

  it("keeps command filters and focus entirely in the presentation SFC", () => {
    expect(commandsSource).not.toContain("defineEmits");
    expect(commandsSource).not.toContain("emit(");
    expect(commandsSource).toContain("const visibleCommands = computed");
    expect(commandsSource).toContain("const focusBanner = computed");
  });

  it("leaves telemetry query-state interactions outside the host binding set", () => {
    expect(telemetrySource).not.toContain("defineEmits");
    expect(telemetrySource).not.toContain("emit(");
    expect(telemetrySource).toContain('pushEvent("apply_filters"');
    expect(telemetrySource).toContain('pushEvent("apply_question"');
    expect(telemetrySource).toContain('pushEvent("add_to_dashboard"');
    expect(telemetrySource).not.toContain("navigateQuery");
    expect(telemetrySource).not.toContain("pendingFilterSubmission");
    expect(telemetrySource).not.toContain("pendingAddSubmission");
  });

  it("retains every data-operation event as a host-owned action", () => {
    for (const action of [
      "validate-request",
      "record-historical-workflow-request",
      "transition-group",
      "retry-group",
      "request-correction",
    ]) {
      expect(dataOperationsSource).toContain(`emit("${action}"`);
    }

    expect(dataOperationsSource).not.toContain("pendingValidations");
  });
});
