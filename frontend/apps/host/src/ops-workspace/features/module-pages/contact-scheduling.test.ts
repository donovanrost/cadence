import "../../../module-pages.test-support";
import type { OpsPageAction } from "@cadence/plugin-sdk/ops-pages";
import { required } from "../../../../../../test-support/required";
import { mount, flushPromises } from "@vue/test-utils";
import { pageHeaderHarness } from "@cadence/plugin-sdk/page-header-testing";
import { expect, test, vi } from "vite-plus/test";
import OpsModulePage from "./OpsModulePage.vue";
import {
  contactPage,
  contactOperation,
  completedContact,
} from "../../../../../../modules/planning-and-contacts/src/features/contact-scheduling/contact-workflow.test-support";
import type { ReservationDetail } from "../../../../../../modules/planning-and-contacts/src/features/contact-scheduling/OpsContactDetail.contracts";
test("host captures reservation identity, query port and token for native decision recovery", async () => {
  const data = contactPage("reservation"),
    model = data.model as ReservationDetail;
  const initial = {
    id: "planning.reservation-review",
    slot: "ops.page",
    version: 1,
    status: "ready",
    token: "11111111-1111-4111-8111-111111111111",
    data,
    context: {
      organizationId: model.context.organization_id,
      missionId: model.context.mission_id,
      resourceId: model.reservation.id,
    },
  };
  const query = vi.fn(),
    refresh = vi.fn();
  const execute = vi.fn(async ({ event, input }: OpsPageAction) => {
    if (event !== "approve-provider-change") throw Error("Unexpected host action");
    query.mockResolvedValue({
      ...initial,
      data: completedContact(data, contactOperation(data, event, input)),
    });
    throw Error("lost response");
  });
  const w = mount(
    pageHeaderHarness("/missions/:mission_id/ops/contacts/:provider_reservation_id").stage(
      OpsModulePage,
    ),
    {
      props: {
        contributionId: initial.id,
        snapshot: initial,
        context: initial.context,
        execute,
        query,
        refresh,
        navigate: vi.fn(),
      },
    },
  );
  try {
    await w.get("#approve-provider-change-reason").setValue("Reviewed host proposal");
    await w.get("#approve-provider-change-form").trigger("submit");
    await flushPromises();
    expect(execute).toHaveBeenCalledOnce();
    expect(required(execute.mock.calls[0])[0]).toMatchObject({
      id: initial.id,
      token: initial.token,
      event: "approve-provider-change",
      input: { sequence: 1, payload: { provider_reservation_id: model.reservation.id } },
    });
    await w.get("#page-header-refresh").trigger("click");
    await flushPromises();
    expect(query).toHaveBeenCalledExactlyOnceWith({ id: initial.id, token: initial.token });
    expect(w.get("#reservation-receipt").text()).toContain("approved");
    expect(refresh).not.toHaveBeenCalled();
    await w.setProps({ context: { ...initial.context, resourceId: "foreign" } });
    expect(w.find("#ops-module-unavailable").exists()).toBe(true);
  } finally {
    w.unmount();
  }
});
