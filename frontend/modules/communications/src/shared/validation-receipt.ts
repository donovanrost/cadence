import { record, invalid } from "./read-validation.ts";
export function validationResult(receipt: unknown) {
  const envelope = record(receipt);
  const result = record(envelope.result ?? envelope);
  if (result.valid !== true) return invalid();
  return result;
}
