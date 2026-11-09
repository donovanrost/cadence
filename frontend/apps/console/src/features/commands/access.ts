import { computed, type ComputedRef } from "vue";
import { organizationCapabilities, useConsoleScope, useSession } from "@/shell/index.ts";

/**
 * Who may command (DECISIONS #38): only what the server reports for the organization that owns
 * the mission on screen, from the same policy it enforces. Never inferred from a role name.
 */
export const COMMAND_REQUEST = "command.request";
export const COMMAND_APPROVE = "command.approve";
/** From the check abort enforces (9817aea3); follows #31 when enforcement changes. */
export const COMMAND_ABORT = "command.abort";

export type CommandAccess = Readonly<{ request: boolean; approve: boolean; abort: boolean }>;

const NONE: CommandAccess = { request: false, approve: false, abort: false };

export function commandAccess(capabilities: ReadonlySet<string>): CommandAccess {
  return {
    request: capabilities.has(COMMAND_REQUEST),
    approve: capabilities.has(COMMAND_APPROVE),
    abort: capabilities.has(COMMAND_ABORT),
  };
}

/** No organization in the URL means no commanding. */
export function useCommandAccess(): ComputedRef<CommandAccess> {
  const session = useSession();
  const scope = useConsoleScope();
  return computed(() => {
    const s = scope.value;
    return s.kind === "mission" || s.kind === "organization" || s.kind === "unknown-mission"
      ? commandAccess(organizationCapabilities(session, s.organization))
      : NONE;
  });
}
