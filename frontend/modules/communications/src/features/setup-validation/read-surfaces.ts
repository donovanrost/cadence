import CommsValidation from "./CommsValidation.vue";
import { readValidation } from "./read-validation";
export const readSurfaces = {
  validation: { component: CommsValidation, admit: readValidation },
} as const;
