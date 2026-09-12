import { mount, flushPromises } from "@vue/test-utils";
import { expect, test, vi } from "vite-plus/test";
import OpsModulePage from "./OpsModulePage.vue";
import {
  declarationFixture,
  declarationOperation,
} from "../../../../../../modules/planning-and-contacts/src/features/contact-requirements/declaration.test-support";
test("host captures the declaration token, guards pending save and recovers the actual receipt", async () => {
  const initial = {
    id: "planning.requirement-declaration",
    slot: "ops.page",
    version: 1,
    status: "ready",
    token: "11111111-1111-4111-8111-111111111111",
    context: { organizationId: "org-1", missionId: "mission-1" },
    data: declarationFixture(),
  };
  const query = vi.fn(),
    refresh = vi.fn(),
    dispose = vi.fn();
  let guard = () => true;
  const execute = vi.fn(async ({ event, input }) => {
    const op = declarationOperation(initial.data, event, input);
    query.mockResolvedValue({
      ...initial,
      data: { ...initial.data, sequence: op.sequence, operation: op },
    });
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
    await w.get("#contact-requirement-form").trigger("submit");
    await flushPromises();
    expect(execute).toHaveBeenCalledExactlyOnceWith(
      expect.objectContaining({
        id: initial.id,
        token: initial.token,
        event: "save",
        input: {
          sequence: 1,
          payload: expect.objectContaining({ contact_requirement: expect.any(Object) }),
        },
      }),
    );
    await w.get("#requirement-declaration-refresh").trigger("click");
    await flushPromises();
    expect(query).toHaveBeenCalledExactlyOnceWith({ id: initial.id, token: initial.token });
    expect(w.find("#requirement-declaration-receipt").exists()).toBe(true);
    expect(refresh).not.toHaveBeenCalled();
    expect(guard()).toBe(true);
    await w.setProps({
      snapshot: { ...initial, context: { ...initial.context, missionId: "foreign" } },
    });
    expect(w.find("#ops-module-unavailable").exists()).toBe(true);
  } finally {
    w.unmount();
  }
  expect(dispose).toHaveBeenCalledOnce();
});
