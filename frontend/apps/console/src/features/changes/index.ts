/** Public API of the changes feature. */
export { default as ConfigStatus } from "./ConfigStatus.vue";
export { default as StagedBar } from "./StagedBar.vue";
export { default as FailureOutcomeCallout } from "./FailureOutcomeCallout.vue";
export { useStageFailure } from "./useStageFailure.ts";
export { default as StagedArchive } from "./StagedArchive.vue";
export { refusalOutcome, type RefusalOutcome } from "./refusals.ts";
export {
  errorCode,
  failureOutcome,
  type FailureOutcome,
  invalidOpDetails,
  type PreviewItem,
  previewOps,
  previewReader,
  type Preview,
  rejectionSentence,
  stageChange,
  type StageOp,
  type StageResult,
} from "./actions.ts";
export { itemLine } from "./itemLines.ts";
export { kindLabel } from "./shapes.ts";
export { checkKeyText, checkLabel, type CheckKey, type HoldReason } from "./preview.ts";
export { refreshConfigState, useConfigState } from "./useConfigState.ts";
export { default as SchemaForm } from "./SchemaForm.vue";
export { default as KindEditor } from "./KindEditor.vue";
export type { Change, FormRules, FormState } from "./formRules.ts";
export {
  diffEdits,
  displayValue,
  fetchKindSchema,
  fromDocument,
  kindSchemaReader,
  schemaFieldReader,
  toValue,
  visible,
  type SchemaField,
  type EditableKind,
  type FormValues,
  type KindSchema,
} from "./kindSchema.ts";
export type { ChangeSet, RevisionDetail } from "./shapes.ts";
export { fetchEntityRevisions } from "./api.ts";
export { default as FieldRows } from "./FieldRows.vue";
/** U89 record lines with the ADMIN MODE tag (P3 #227), shared with activations. */
export { default as RecordLine } from "./RecordLine.vue";
export type { HeaderPart } from "./revision-record.ts";
