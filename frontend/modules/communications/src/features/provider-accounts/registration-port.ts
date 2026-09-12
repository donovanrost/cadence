import type { ProviderAccountPayload } from "./registration.contracts";
export { FormActionFailure as RegistrationActionFailure } from "../../shared/form-workflow.contracts";
export type RegistrationPort = {
  execute(action: "validate" | "save", input: ProviderAccountPayload): Promise<unknown>;
  navigate(href: string): void;
};
