/** Dashboard-owned presentation. Host registration and route admission are separate. */
export { default as DiagnosticsLegacyRedirect } from "./features/execution-diagnostics/DiagnosticsLegacyRedirect.vue";
export { executionDiagnosticsContribution } from "./features/execution-diagnostics/contribution";
export { readDiagnosticsPage, diagnosticsHref } from "./features/execution-diagnostics/page-state";
export type { DiagnosticsPageState } from "./features/execution-diagnostics/page-state";
export { default as ExecutionDiagnosticsView } from "./features/execution-diagnostics/ExecutionDiagnostics.vue";
export { readExecutionDiagnostics } from "./features/execution-diagnostics/validation";
export { initialSelection, readSelection } from "./features/execution-diagnostics/selection";
export type { DiagnosticSelection } from "./features/execution-diagnostics/selection";
export { collectionIds } from "./features/execution-diagnostics/contracts";
export type {
  ExecutionDiagnostics,
  DiagnosticCollection,
  DiagnosticRow,
} from "./features/execution-diagnostics/contracts";
