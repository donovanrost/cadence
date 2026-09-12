export type FormInput = Record<string, Record<string, string>>;
export class FormActionFailure extends Error {
  constructor(readonly outcome: "rejected" | "unknown") {
    super("The form action could not be completed.");
  }
}
export type FormPort = {
  execute(action: "validate" | "save", input: FormInput): Promise<unknown>;
  navigate(href: string): void;
};
export type FormFeedback = {
  canSubmit: boolean;
  validating: boolean;
  saving: boolean;
  canRevalidate: boolean;
  message: string | null;
};
