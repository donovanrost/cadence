import { providerAccountActions } from "./actions";
export { FormActionFailure as AccountActionFailure } from "../../shared/form-workflow.contracts";
export type AccountDetailAction = keyof typeof providerAccountActions.provider_account_show;
export type AccountDetailPort = {
  execute(action: AccountDetailAction, input: Record<string, unknown>): Promise<unknown>;
  query(): Promise<unknown>;
};
