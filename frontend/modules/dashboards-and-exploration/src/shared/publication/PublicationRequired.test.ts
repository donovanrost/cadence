import { mount, flushPromises } from "@vue/test-utils";
import { expect, test, vi } from "vite-plus/test";
import { executionDiagnosticsContribution } from "../../features/execution-diagnostics/contribution";
import { readPublicationRequirement } from "./contracts";
const context = { organizationId: "org-1", missionId: "mission-1", resourceId: "dashboard-1" };
const requirement = {
  state: "publication_required",
  version: 1,
  organization_id: "org-1",
  mission_id: "mission-1",
  dashboard_id: "dashboard-1",
  author: true,
};
test("publication notice rejects cross-scope identity, unknown versions and draft content", () => {
  expect(readPublicationRequirement(requirement, context)).toEqual(requirement);
  for (const bad of [
    { ...requirement, version: 2 },
    { ...requirement, author: "true" },
    { ...requirement, organization_id: "foreign" },
    { ...requirement, mission_id: "foreign" },
    { ...requirement, dashboard_id: "foreign" },
    { ...requirement, name: "Private draft" },
  ])
    expect(() => readPublicationRequirement(bad, context)).toThrow();
});
for (const contribution of [executionDiagnosticsContribution]) {
  test(`${contribution.id} renders a scoped publication notice without resolving or inspecting drafts`, async () => {
    const execute = vi.fn(),
      refresh = vi.fn().mockRejectedValue(Error("private failure"));
    const wrapper = mount(contribution.component, {
      props: {
        ...contribution.read(requirement, context),
        port: { execute, navigate: vi.fn((_: string) => {}) },
        refresh,
      },
    });
    expect(wrapper.find("#dashboard-publication-required").exists()).toBe(true);
    expect(wrapper.get("#dashboard-publication-editor").attributes("href")).toBe(
      "/missions/mission-1/ops/dashboards/dashboard-1/edit",
    );
    expect(wrapper.find("#dashboard-workspace-feature").exists()).toBe(false);
    await wrapper.get("#dashboard-publication-refresh").trigger("click");
    await flushPromises();
    expect(refresh).toHaveBeenCalledOnce();
    expect(execute).not.toHaveBeenCalled();
    expect(wrapper.get('[role="status"]').text()).toContain("could not be checked");
    expect(wrapper.text()).not.toContain("private failure");
    expect(wrapper.get("#dashboard-publication-refresh").attributes("disabled")).toBeUndefined();
    await wrapper.setProps(contribution.read({ ...requirement, author: false }, context));
    expect(wrapper.find("#dashboard-publication-editor").exists()).toBe(false);
    wrapper.unmount();
  });
}
