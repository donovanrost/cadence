import { expectTypeOf, test } from "vite-plus/test";
import type {
  SourceCommand,
  SourceInputs,
  SourceOperation,
  SourcePage,
} from "./data-sources/native-contract";
import type {
  HistoryCommand,
  HistoryInputs,
  HistoryOperation,
  HistoryPage,
} from "./historical-workflows/native-contract";
import type { useDataSources } from "./data-sources/native-state";
import type { useHistoricalWorkflows } from "./historical-workflows/native-state";

test("actions require their own payload and result shape", () => {
  expectTypeOf<{
    action: "change-binding";
    input: SourceInputs["register-source"];
  }>().not.toExtend<SourceCommand>();
  expectTypeOf<{
    action: "request-correction";
    input: HistoryInputs["retry-group"];
  }>().not.toExtend<HistoryCommand>();
  expectTypeOf<{
    action: "register-source";
    id: string;
    sequence: number;
    feedback: string[];
    input: SourceInputs["register-source"];
    status: "completed";
    result: null;
  }>().not.toExtend<SourceOperation>();
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
    source: SourcePage,
    history: HistoryPage,
    sources: ReturnType<typeof useDataSources>,
    workflows: ReturnType<typeof useHistoricalWorkflows>,
  ) => {
    // @ts-expect-error Admitted source rows are readonly; mutable form drafts are separate.
    source.model.sources.entries = [];
    // @ts-expect-error Server permissions cannot be changed by the presentation layer.
    history.model.permissions.manage = true;
    const registration: SourceInputs["register-source"] = {
      params: { source: source.model.defaults },
      review: {},
      confirmed: true,
    };
    // @ts-expect-error Binding changes cannot take registration payloads.
    void sources.execute("change-binding", registration);
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
