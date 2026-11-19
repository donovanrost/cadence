import { readForm as routing } from "./features/routing/form-validation.ts";
import type { ReadContext } from "./shared/read-contracts.ts";
export { default as RoutingCreation } from "./features/routing/RoutingCreation.vue";
export type { FormPort } from "./shared/form-workflow.contracts";
export { FormActionFailure } from "./shared/form-workflow.contracts";
/** §11c comms batch 1 (director): the transport and ground-station forms left; routing until Extra route. */
const forms = {
  routing_new: routing,
} as const;

export function admitFormSurface(
  surfaceId: string,
  version: number,
  payload: unknown,
  context: ReadContext,
) {
  if (version !== 1 || !Object.hasOwn(forms, surfaceId))
    throw new Error("Unsupported Communications form surface.");
  return forms[surfaceId as keyof typeof forms](payload, context);
}
