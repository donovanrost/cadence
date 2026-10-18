import { diagnosticsContributions } from "@cadence/dashboards-and-exploration";
import { ADMINISTRATION_DIAGNOSTICS_SLOT, type DiagnosticsContribution } from "@cadence/plugin-sdk";
import type { Component } from "vue";

/** Explicit compiled admission, not component names or imports supplied by a server response. */
export function admitDiagnostics(contributions: readonly DiagnosticsContribution<Component>[]) {
  const ids = new Set<string>();
  for (const item of contributions) {
    if (
      item.slot !== ADMINISTRATION_DIAGNOSTICS_SLOT ||
      item.version !== 1 ||
      !/^[a-z][a-z0-9.-]+$/.test(item.id) ||
      ids.has(item.id) ||
      !Number.isSafeInteger(item.order)
    ) {
      throw new Error("Invalid administration diagnostics registration.");
    }
    ids.add(item.id);
  }
  return Object.freeze(
    [...contributions].sort((a, b) => a.order - b.order || a.id.localeCompare(b.id)),
  );
}

export const administrationDiagnostics = admitDiagnostics(diagnosticsContributions);
