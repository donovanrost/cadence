import { expectTypeOf, test } from "vite-plus/test";
import type { PolicyCommand, PolicyInputs, PolicyOperation, PolicyResults } from "./fleet-policy";
import type { PolicyActionPort } from "./policy-action-port";

test("policy actions, receipts, and completion states remain correlated", () => {
  expectTypeOf<{
    action: "approve-policy";
    input: PolicyInputs["issue-grant"];
  }>().not.toExtend<PolicyCommand>();
  expectTypeOf<{
    action: "save-policy";
    sequence: number;
    input: PolicyInputs["save-policy"];
    status: "completed";
    receipt: null;
  }>().not.toExtend<PolicyOperation>();
  expectTypeOf<{
    action: "approve-policy";
    sequence: number;
    input: PolicyInputs["approve-policy"];
    status: "completed";
    receipt: { receiptId: string; completedAt: string; result: PolicyResults["issue-grant"] };
  }>().not.toExtend<PolicyOperation>();
  type Approval = Extract<PolicyOperation, { action: "approve-policy" }>;
  const approve = (port: PolicyActionPort, input: PolicyInputs["approve-policy"]) =>
    port.execute({ action: "approve-policy", sequence: 1, input });
  expectTypeOf<Awaited<ReturnType<typeof approve>>>().toEqualTypeOf<Approval>();
});
