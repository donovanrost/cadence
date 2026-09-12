import { registrationFixture } from "./provider-accounts.test-support";
import { readRegistration, registrationFields } from "./registration.validation";
import type { ProviderAccountValues } from "./registration.contracts";
export const registrationModel = () => readRegistration(registrationFixture(), 1);
export function receipt(result: unknown) {
  return { receiptId: "receipt-1", completedAt: "2026-09-07T10:00:00Z", result };
}
export function validationReceipt(values: ProviderAccountValues) {
  const { form } = registrationModel();
  for (const field of registrationFields(form)) field.value = values[field.key] ?? field.value;
  form.connector.selected.form_value = form.fields.provider_type.value;
  return receipt({ patch: { form } });
}
export function deferred<T>() {
  let resolve!: (value: T) => void, reject!: (reason: unknown) => void;
  const promise = new Promise<T>((yes, no) => {
    resolve = yes;
    reject = no;
  });
  return { promise, resolve, reject };
}
