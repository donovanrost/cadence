import { required } from "../../../test-support/required";
import { flushPromises, mount } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import type {
  FullPageSurfaceProps,
  HostActionReceipt,
  HostActionRequest,
  HostBridge,
  HostContext,
  HostQueryRequest,
} from "@cadence/plugin-sdk";
import OrganizationAdminApplication from "./OrganizationAdminApplication.vue";
import { manifest } from "./federated-application";
import { SURFACE_CONTRACTS } from "./organization-admin-contract";

const context: HostContext = {
  scope: "organization",
  missionId: null,
  missionName: null,
  spacecraftId: null,
  spacecraftName: null,
  organizationId: "org-1",
  actor: { displayName: "Mara Vance", permissions: ["applications:view"] },
};

function propsFor(
  surface: FullPageSurfaceProps["surface"],
  query: HostBridge["query"],
): FullPageSurfaceProps {
  const application = {
    applicationKey: "organization_admin",
    applicationVersion: 1,
    displayName: "Organization Administration",
    description: "Organization administration.",
    package: { packageId: "cadence.organization-admin", version: 1 },
    surface,
    release: {
      federation: "module_federation" as const,
      releaseId: "organization-admin-v1",
      remoteName: "cadence_organization_admin",
      manifestUrl: "/assets/application-host/organization-admin/mf-manifest.json",
      exposedModule: "./Application",
    },
  };

  return {
    application,
    surface,
    context,
    bridge: {
      query,
      execute: actionBridgeMock().bridge,
      subscribe: vi.fn(),
    },
  };
}

function queryBridgeMock() {
  const mock = vi.fn((_request: HostQueryRequest) =>
    Promise.resolve<unknown>({
      queryVersion: 1,
      presentation: {},
    }),
  );
  const bridge: HostBridge["query"] = async <TResult>(request: HostQueryRequest) =>
    (await mock(request)) as TResult;
  return { bridge, mock };
}

function actionBridgeMock() {
  const mock = vi.fn((_request: HostActionRequest<unknown>) =>
    Promise.resolve<HostActionReceipt<unknown>>({
      receiptId: "receipt-1",
      completedAt: "2026-09-04T00:00:00Z",
      result: {},
    }),
  );
  const bridge: HostBridge["execute"] = async <_TInput, TResult>(
    request: HostActionRequest<_TInput>,
  ) => (await mock(request)) as HostActionReceipt<TResult>;
  return { bridge, mock };
}

const rendererStubs = Object.fromEntries(
  SURFACE_CONTRACTS.map(({ component }) => [
    component,
    { template: `<div data-test-legacy-renderer="${component}" />` },
  ]),
);

rendererStubs.FederatedNotificationBell = required(rendererStubs.NotificationsBell);

afterEach(() => vi.restoreAllMocks());

describe("Organization Admin federated adapter", () => {
  it.each(SURFACE_CONTRACTS)(
    "selects $surfaceId, queries its declared DTO, and mounts its legacy component",
    async (contract) => {
      const surface = required(
        manifest.surfaces.find(({ surfaceId }) => surfaceId === contract.surfaceId),
      );
      const { bridge: query, mock: queryMock } = queryBridgeMock();
      const wrapper = mount(OrganizationAdminApplication, {
        props: propsFor(surface, query),
        global: { stubs: rendererStubs },
      });

      await flushPromises();

      expect(queryMock).toHaveBeenCalledWith({
        queryId: contract.query.id,
        version: contract.query.version,
        context,
      });
      expect(wrapper.find("#organization-admin-application").attributes()).toMatchObject({
        "data-organization-admin-surface": contract.surfaceId,
        "data-organization-admin-renderer": contract.component,
      });
      expect(wrapper.find(`[data-test-legacy-renderer="${contract.component}"]`).exists()).toBe(
        true,
      );
      wrapper.unmount();
    },
  );
});

it("the legacy bell validates its host recipient and navigates without a duplicate read action", async () => {
  const surface = required(
    manifest.surfaces.find(({ surfaceId }) => surfaceId === "notifications_bell"),
  );
  const { bridge: query, mock: queryMock } = queryBridgeMock();
  const model = {
    version: 1,
    user: { user_id: "bell-recipient" },
    unread_count: 1,
    notifications: [{ notification_id: "notice", title: "Notice", body: null, read_at: null }],
  };
  queryMock.mockResolvedValue({ queryVersion: 1, presentation: { context: model } });
  const props = propsFor(surface, query);
  props.context = {
    scope: "user",
    organizationId: null,
    userId: "bell-recipient",
    missionId: null,
    missionName: null,
    spacecraftId: null,
    spacecraftName: null,
    actor: context.actor,
  };
  const { bridge: execute, mock: executeMock } = actionBridgeMock();
  props.bridge.execute = execute;
  const wrapper = mount(OrganizationAdminApplication, { props, attachTo: document.body });
  await flushPromises();
  await wrapper.get("#notifications-bell-application").trigger("click");
  expect(wrapper.get("a").attributes("href")).toBe("/notifications");
  await wrapper.get("a").trigger("click");
  expect(executeMock).not.toHaveBeenCalled();
  await wrapper.setProps({ context: { ...props.context, userId: "another-recipient" } });
  await flushPromises();
  expect(wrapper.find("#notifications-bell-application").exists()).toBe(false);
  expect(wrapper.find("#notifications-bell-application-unavailable").exists()).toBe(true);
  wrapper.unmount();
});
