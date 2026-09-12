import { mount, flushPromises } from "@vue/test-utils";
import { expect, test, vi } from "vite-plus/test";
import OpsModulePage from "./OpsModulePage.vue";
import {
  reviewFixture,
  reviewOperation,
  completedReview,
} from "../../../../../../modules/planning-and-contacts/src/features/contact-plans/plan-review.test-support";
test("host captures the plan resource and token and recovers the native submission receipt", async () => {
  const data = reviewFixture(),
    initial = {
      id: "planning.plan-review",
      slot: "ops.page",
      version: 1,
      status: "ready",
      token: "11111111-1111-4111-8111-111111111111",
      data,
      context: {
        organizationId: data.detail.context.organization_id,
        missionId: data.detail.context.mission_id,
        resourceId: data.detail.plan.id,
      },
    };
  const query = vi.fn(),
    refresh = vi.fn(),
    dispose = vi.fn();
  let guard = () => true;
  const execute = vi.fn(async ({ event, input }) => {
    query.mockResolvedValue({
      ...initial,
      data: completedReview(data, reviewOperation(data, event, input)),
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
    await w.get("#submission-reason").setValue("Reviewed host proposal");
    await w.get("#submission").trigger("submit");
    await flushPromises();
    expect(execute).toHaveBeenCalledOnce();
    expect(execute.mock.calls[0]![0]).toMatchObject({
      id: initial.id,
      token: initial.token,
      event: "submit-plan",
      input: { sequence: 1, payload: { contact_plan_id: data.detail.plan.id } },
    });
    await w.get("#refresh-plan-review").trigger("click");
    await flushPromises();
    expect(query).toHaveBeenCalledExactlyOnceWith({ id: initial.id, token: initial.token });
    expect(w.get("#plan-operation-receipt").text()).toContain("submit-plan");
    expect(w.get("#approval-reason").attributes("disabled")).toBeUndefined();
    expect(refresh).not.toHaveBeenCalled();
    expect(guard()).toBe(true);
    await w.setProps({ context: { ...initial.context, resourceId: "foreign" } });
    expect(w.find("#ops-module-unavailable").exists()).toBe(true);
  } finally {
    w.unmount();
  }
  expect(dispose).toHaveBeenCalledOnce();
});
