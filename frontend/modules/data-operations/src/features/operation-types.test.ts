import { expectTypeOf, test } from "vite-plus/test";
import type {
  HistoryCommand,
  HistoryInputs,
  HistoryOperation,
  HistoryPage,
} from "./historical-workflows/native-contract";
import type { useHistoricalWorkflows } from "./historical-workflows/native-state";

// L11 removed the native data-sources page and its contract; historical workflows (L16) remain.
test("actions require their own payload and result shape", () => {
  expectTypeOf<{
    action: "request-correction";
    input: HistoryInputs["retry-group"];
  }>().not.toExtend<HistoryCommand>();
  expectTypeOf<{
    action: "record-request";
    id: string;
    sequence: number;
    feedback: string[];
    input: HistoryInputs["record-request"];
    status: "completed";
    result: { valid: boolean };
  }>().not.toExtend<HistoryOperation>();
});

test("snapshots and execution entry points retain their compile-time constraints", () => {
  const contracts = (
    history: HistoryPage,
    workflows: ReturnType<typeof useHistoricalWorkflows>,
  ) => {
    // @ts-expect-error Server permissions cannot be changed by the presentation layer.
    history.model.permissions.manage = true;
    // @ts-expect-error Corrections require the selected event identity.
    void workflows.execute("request-correction", {
      group_id: "group",
      evidence: "hash",
      reason: "reason",
      confirmed: true,
    });
  };
  expectTypeOf(contracts).toBeFunction();
});
