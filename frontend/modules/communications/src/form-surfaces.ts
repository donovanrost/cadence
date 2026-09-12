import { readForm as transport } from "./features/transports/form-validation.ts";
import { readForm as routing } from "./features/routing/form-validation.ts";
import {
  readForm as station,
  readEditForm as editStation,
} from "./features/ground-stations/form-validation.ts";
import type { ReadContext } from "./shared/read-contracts.ts";
export { default as TransportCreation } from "./features/transports/TransportCreation.vue";
export { default as RoutingCreation } from "./features/routing/RoutingCreation.vue";
export { default as GroundStationEditor } from "./features/ground-stations/GroundStationEditor.vue";
export type { FormPort } from "./shared/form-workflow.contracts";
export { FormActionFailure } from "./shared/form-workflow.contracts";
const forms = {
  transport_new: transport,
  routing_new: routing,
  ground_station_new: station,
  ground_station_edit: editStation,
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
