import { ADMINISTRATION_DIAGNOSTICS_SLOT, type DiagnosticsContribution } from "@cadence/plugin-sdk";
import type { Component } from "vue";
import RuntimeDiagnosticsContribution from "./RuntimeDiagnosticsContribution.vue";
import { assertRuntimeDiagnostics } from "./validation";

export const runtimeDiagnosticsContribution: DiagnosticsContribution<Component> = Object.freeze({
  id: "dashboards.runtime-diagnostics",
  slot: ADMINISTRATION_DIAGNOSTICS_SLOT,
  version: 1,
  title: "Dashboard runtime diagnostics",
  order: 100,
  component: RuntimeDiagnosticsContribution,
  validate: assertRuntimeDiagnostics,
});
