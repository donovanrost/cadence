import CommsValidation from "./CommsValidation.vue";
import { readValidation } from "./read-validation";
export const readSurfaces = {
  // oxlint-disable-next-line typescript/no-unsafe-assignment -- vue-tsc checks the SFC constructor at this registration or render boundary.
  validation: { component: CommsValidation, admit: readValidation },
} as const;
