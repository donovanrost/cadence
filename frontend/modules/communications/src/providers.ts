export { readList, readDetail } from "./features/providers/read-validation.ts";
export { readForm } from "./features/providers/form-validation.ts";
export { default as ProviderCreation } from "./features/providers/ProviderCreation.vue";
export { default as ProviderDetail } from "./features/providers/ProviderDetail.vue";
export { default as ProviderList } from "./features/providers/CommsProviderList.vue";
export type { ProviderPort } from "./features/providers/provider-port";
import { readList, readDetail } from "./features/providers/read-validation.ts";
import { readForm } from "./features/providers/form-validation.ts";
import type { ReadContext } from "./shared/read-contracts.ts";
export function admitProviderSurface(
  surface: string,
  version: number,
  payload: unknown,
  context: ReadContext,
) {
  if (version !== 1) throw new Error("Unsupported provider surface version.");
  switch (surface) {
    case "provider_list":
      return readList(payload, context);
    case "provider_new":
      return { model: readForm(payload, context) };
    case "provider_show":
      return { model: readDetail(payload, context) };
    default:
      throw new Error("Unsupported provider surface.");
  }
}
