import type { OpsPagePort } from "@cadence/plugin-sdk/ops-pages";
import { admitPolicyOperation, equalPolicyData } from "./fleet-policy";
import type {
  PolicyAction,
  PolicyContext,
  PolicyOperation,
  SequencedPolicyCommand,
} from "./fleet-policy";

type Request<A extends PolicyAction> = Extract<SequencedPolicyCommand, { action: A }>;
type Reply<A extends PolicyAction> = Extract<PolicyOperation, { action: A }>;
export type PolicyActionPort = {
  execute<A extends PolicyAction>(request: Request<A>): Promise<Reply<A>>;
};

function matches<A extends PolicyAction>(
  operation: PolicyOperation | null,
  request: Request<A>,
): operation is Reply<A> {
  return (
    operation !== null &&
    operation.sequence === request.sequence &&
    operation.action === request.action &&
    equalPolicyData(operation.input, request.input)
  );
}

export function createPolicyActionPort(
  transport: Pick<OpsPagePort, "execute">,
  context: PolicyContext,
): PolicyActionPort {
  return {
    async execute(request) {
      const response: unknown = await transport.execute(request.action, {
        sequence: request.sequence,
        payload: request.input,
      });
      const operation = admitPolicyOperation(response, context);
      if (!matches(operation, request)) throw Error("Different or unavailable policy operation");
      return operation;
    },
  };
}
