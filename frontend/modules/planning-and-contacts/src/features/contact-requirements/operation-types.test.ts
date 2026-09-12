import { expect, test } from "vite-plus/test";
import { declarationFixture, declarationOperation } from "./declaration.test-support";
import { templateEntry, templateFixture, templateOperation } from "./templates.test-support";
import {
  requirementPageFixture,
  requirementOperationFixture,
} from "./requirement-workflow.test-support";
import { decision } from "./requirement-detail";
import {
  admitDeclarationOperation,
  declarationDefaults,
  type DeclarationOperation,
  type DeclarationRequest,
} from "./declaration";
import { admitTemplateOperation, type TemplateOperation, type TemplateRequest } from "./templates";
import {
  admitRequirementOperation,
  requirementContext,
  type RequirementOperation,
  type RequirementRequest,
} from "./requirement-workflow";

// These calls are checked by the workspace compiler and never execute.
function checkRejectedPrograms(
  declaration: DeclarationOperation,
  template: TemplateOperation,
  requirement: RequirementOperation,
) {
  const declare = (...request: DeclarationRequest) => request;
  const recur = (...request: TemplateRequest) => request;
  const plan = (...request: RequirementRequest) => request;
  // @ts-expect-error Saving requires the declaration fields, not a spacecraft page.
  declare("save", { page: 2 });
  // @ts-expect-error A lifecycle action requires the displayed template reference.
  recur("pause-template", { template: {} });
  // @ts-expect-error Creating a plan requires the selected run and opportunity ids.
  plan("create-plan", decision(requirementPageFixture().detail));
  if (declaration.status === "completed") {
    // @ts-expect-error A completed operation always owns its receipt.
    const missing: DeclarationOperation = { ...declaration, receipt: null };
    void missing;
    if (declaration.action === "save") {
      // @ts-expect-error Save results cannot substitute validation feedback.
      void declaration.receipt.result.valid;
    }
    // @ts-expect-error Admitted receipt data is readonly.
    declaration.receipt.completedAt = "changed";
  }
  if (template.status === "completed" && template.action === "pause-template") {
    // @ts-expect-error A pause receipt proves the paused lifecycle state.
    const active: "active" = template.receipt.result.reference.lifecycle_state;
    void active;
  }
  if (requirement.status !== "completed") {
    // @ts-expect-error Unconfirmed and rejected operations cannot expose results.
    void requirement.receipt.result;
  }
  // @ts-expect-error Reviewed evidence cannot be edited through an admitted command.
  requirement.input.requirement_evidence.requirement_version = 3;
}
void checkRejectedPrograms;

test("declaration receipts preserve action, actor and validated feedback relationships", () => {
  const page = declarationFixture();
  const save = declarationOperation(page, "save", {
    sequence: 1,
    payload: { contact_requirement: declarationDefaults(page.model) },
  });
  expect(admitDeclarationOperation(save, page.model.context)).toEqual(save);
  for (const operation of [
    { ...save, receipt: null },
    { ...save, input: { page: 1 } },
    { ...save, receipt: { ...save.receipt, result: { valid: true, feedback: [] } } },
    {
      ...save,
      receipt: { ...save.receipt, result: { ...save.receipt.result, actor_id: "other" } },
    },
    { ...save, status: "rejected", receipt: null, feedback: ["unknown_feedback"] },
  ])
    expect(admitDeclarationOperation(operation, page.model.context)).toBeNull();
  expect(
    admitDeclarationOperation(
      { ...save, status: "rejected", receipt: null, feedback: ["horizon_order"] },
      page.model.context,
    )?.status,
  ).toBe("rejected");
});

test("template receipts retain the exact reviewed reference and action-specific lifecycle", () => {
  const page = templateFixture();
  const pause = templateOperation(page, "pause-template", {
    sequence: 1,
    payload: { reference: templateEntry(page).reference },
  });
  for (const operation of [
    { ...pause, action: "activate-template" },
    { ...pause, receipt: null },
    {
      ...pause,
      receipt: {
        ...pause.receipt,
        result: {
          ...pause.receipt.result,
          reference: { ...pause.receipt.result.reference, content_sha256: "f".repeat(64) },
        },
      },
    },
  ])
    expect(admitTemplateOperation(operation, page.model.context)).toBeNull();
  expect(admitTemplateOperation(pause, page.model.context)).toEqual(pause);
});

test("requirement operations admit selected ids and evidence before exposing typed input", () => {
  const page = requirementPageFixture(),
    context = requirementContext(page.detail);
  const create = requirementOperationFixture(page, "create-plan", {
    sequence: 1,
    payload: {
      ...decision(page.detail),
      planning_run_id: "run-1",
      selected_snapshot_ids: ["op-1"],
    },
  });
  for (const status of ["completed", "rejected", "unconfirmed"] as const) {
    const operation = {
      ...create,
      status,
      receipt: status === "completed" ? create.receipt : null,
    };
    expect(admitRequirementOperation(operation, context)?.status).toBe(status);
    expect(
      admitRequirementOperation(
        { ...operation, input: { ...create.input, selected_snapshot_ids: [42] } },
        context,
      ),
    ).toBeNull();
    expect(
      admitRequirementOperation(
        {
          ...operation,
          input: {
            ...create.input,
            requirement_evidence: { ...create.input.requirement_evidence, mission_id: "other" },
          },
        },
        context,
      ),
    ).toBeNull();
  }
});
