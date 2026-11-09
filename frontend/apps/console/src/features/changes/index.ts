/** Public API of the changes feature. */
export { default as ConfigStatus } from "./ConfigStatus.vue";
export { default as StagedBar } from "./StagedBar.vue";
export {
  errorCode,
  failureOutcome,
  type FailureOutcome,
  invalidOpDetails,
  rejectionSentence,
  stageChange,
  type StageOp,
  type StageResult,
} from "./actions.ts";
export { refreshConfigState, useConfigState } from "./useConfigState.ts";
export { default as SchemaForm } from "./SchemaForm.vue";
export { default as KindEditor } from "./KindEditor.vue";
export {
  diffEdits,
  fetchKindSchema,
  fromDocument,
  type EditableKind,
  type FormValues,
  type KindSchema,
} from "./kindSchema.ts";
