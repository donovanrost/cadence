import { admitTemplateReference } from "../../../../../../modules/planning-and-contacts/src/features/contact-requirements/templates";
import type { OpsPageAction } from "@cadence/plugin-sdk/ops-pages";
import { required } from "../../../../../../test-support/required";
import { mount, flushPromises } from "@vue/test-utils";
import { expect, test, vi } from "vite-plus/test";
import OpsModulePage from "./OpsModulePage.vue";
import {
  templateFixture,
  templateEntry,
  templateOperation,
} from "../../../../../../modules/planning-and-contacts/src/features/contact-requirements/templates.test-support";
test("host captures the template token and recovers a lifecycle receipt through the declared read port", async () => {
  const data = templateFixture();
  data.model.templates.entries = [templateEntry(data)];
  const initial = {
    id: "planning.requirement-templates",
    slot: "ops.page",
    version: 1,
    status: "ready",
    token: "11111111-1111-4111-8111-111111111111",
    context: { organizationId: "org-1", missionId: "mission-1" },
    data,
  };
  const query = vi.fn(),
    refresh = vi.fn(),
    dispose = vi.fn();
  let guard = () => true;
  const execute = vi.fn(async ({ event, input }: OpsPageAction) => {
    if (event !== "pause-template") throw Error("Unexpected host action");
    const op = templateOperation(data, event, input),
      recovered = structuredClone(data);
    recovered.sequence = op.sequence;
    recovered.operation = op;
    const reference: unknown = required(op.receipt).result.reference;
    if (!admitTemplateReference(reference, data.model.context))
      throw Error("Missing template receipt reference");
    required(recovered.model.templates.entries[0]).reference = reference;
    query.mockResolvedValue({ ...initial, data: recovered });
    throw Error("Lost response");
  });
  const w = mount(OpsModulePage, {
    props: {
      contributionId: initial.id,
      snapshot: initial,
      context: initial.context,
      execute,
      query,
      refresh,
      navigate: vi.fn(),
      guardNavigation: (g: () => boolean) => {
        guard = g;
        return dispose;
      },
    },
  });
  try {
    await w.get("#pause-template-template-1").trigger("click");
    await flushPromises();
    expect(execute).toHaveBeenCalledExactlyOnceWith({
      id: initial.id,
      token: initial.token,
      event: "pause-template",
      input: {
        sequence: 1,
        payload: { reference: required(data.model.templates.entries[0]).reference },
      },
    });
    await w.get("#requirement-template-refresh").trigger("click");
    await flushPromises();
    expect(query).toHaveBeenCalledExactlyOnceWith({ id: initial.id, token: initial.token });
    expect(w.find("#activate-template-template-1").exists()).toBe(true);
    expect(refresh).not.toHaveBeenCalled();
    expect(guard()).toBe(true);
    await w.setProps({ snapshot: { ...initial, data: {} } });
    expect(w.find("#ops-module-unavailable").exists()).toBe(true);
  } finally {
    w.unmount();
  }
  expect(dispose).toHaveBeenCalledOnce();
});
