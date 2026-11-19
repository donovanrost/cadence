import { containing } from "../../../test-support/matchers";
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
      if (contract.surfaceId === "notifications") {
        expect(wrapper.get("#notifications-destination").attributes("href")).toBe("/notifications");
        expect(wrapper.find("#notifications-panel").exists()).toBe(false);
      } else {
        expect(wrapper.find(`[data-test-legacy-renderer="${contract.component}"]`).exists()).toBe(
          true,
        );
      }
      wrapper.unmount();
    },
  );

  it("rebinds generic action delivery when the adapter context changes", async () => {
    const surface = required(
      manifest.surfaces.find(({ surfaceId }) => surfaceId === "notifications"),
    );
    const { bridge: query } = queryBridgeMock();
    const { bridge: execute, mock: executeMock } = actionBridgeMock();
    const props = propsFor(surface, query);
    props.context = { ...context, scope: "user", organizationId: null, userId: "user-1" };
    props.bridge.execute = execute;
    const wrapper = mount(OrganizationAdminApplication, {
      props,
      global: {
        stubs: {
          NotificationsDestination: {
            template:
              "<button id=\"context-action\" @click=\"$emit('mark-read', { notification_id: 'n-1' })\">Read</button>",
          },
        },
      },
    });
    await flushPromises();
    const nextContext = { ...props.context, actor: { ...context.actor, displayName: "Other" } };
    await wrapper.setProps({ context: nextContext });
    await flushPromises();
    await wrapper.get("#context-action").trigger("click");
    await flushPromises();
    expect(executeMock).toHaveBeenCalledExactlyOnceWith(containing({ context: nextContext }));
    wrapper.unmount();
  });

  it("honors same-origin navigation receipts without issuing a redundant query", async () => {
    const surface = required(
      manifest.surfaces.find(({ surfaceId }) => surfaceId === "notifications"),
    );
    const { bridge: query, mock: queryMock } = queryBridgeMock();
    const { bridge: execute, mock: executeMock } = actionBridgeMock();
    executeMock.mockResolvedValue({
      receiptId: "receipt-navigation-1",
      completedAt: "2026-09-04T00:00:01Z",
      result: { navigation: { href: "/session/organization" } },
    });
    const props = propsFor(surface, query);
    props.context = { ...context, scope: "user", organizationId: null, userId: "user-1" };
    props.bridge.execute = execute;
    const assign = vi.spyOn(window.location, "assign").mockImplementation(() => undefined);
    const wrapper = mount(OrganizationAdminApplication, {
      props,
      global: {
        stubs: {
          NotificationsDestination: {
            template: `<button id="issue" @click="$emit('accept-invitation', { invitation_id: 'inv-1' })" />`,
          },
        },
      },
    });

    await flushPromises();
    await wrapper.get("#issue").trigger("click");
    await flushPromises();
    wrapper.unmount();
    expect(assign).toHaveBeenCalledWith("/session/organization");
    expect(queryMock).toHaveBeenCalledTimes(1);
  });

  it("shows rejection and keeps the newest overlapping action state", async () => {
    const surface = required(
      manifest.surfaces.find(({ surfaceId }) => surfaceId === "notifications"),
    );
    const { bridge: query, mock: queryMock } = queryBridgeMock();
    const first = deferred<Awaited<ReturnType<HostBridge["execute"]>>>();
    const second = deferred<Awaited<ReturnType<HostBridge["execute"]>>>();
    const { bridge: execute, mock: executeMock } = actionBridgeMock();
    executeMock.mockReturnValueOnce(first.promise).mockReturnValueOnce(second.promise);
    const props = propsFor(surface, query);
    props.context = { ...context, scope: "user", organizationId: null, userId: "user-1" };
    props.bridge.execute = execute;
    const wrapper = mount(OrganizationAdminApplication, {
      props,
      global: {
        stubs: {
          NotificationsDestination: {
            template: `<button id="refresh" @click="$emit('mark-read', { notification_id: 'n-1' })" />`,
          },
        },
      },
    });

    await flushPromises();
    await wrapper.get("#refresh").trigger("click");
    await wrapper.get("#refresh").trigger("click");
    second.resolve({
      receiptId: "receipt-organization-2",
      completedAt: "2026-09-04T00:00:02Z",
      result: {},
    });
    await flushPromises();
    first.resolve({
      receiptId: "receipt-organization-1",
      completedAt: "2026-09-04T00:00:01Z",
      result: {},
    });
    await flushPromises();

    expect(wrapper.find("#organization-admin-action-notice").attributes("data-receipt-id")).toBe(
      "receipt-organization-2",
    );
    expect(queryMock).toHaveBeenCalledTimes(2);
    wrapper.unmount();

    const { bridge: rejectedExecute, mock: rejectedExecuteMock } = actionBridgeMock();
    rejectedExecuteMock.mockRejectedValue(new Error("forbidden"));
    const rejectedProps = propsFor(surface, query);
    rejectedProps.context = props.context;
    rejectedProps.bridge.execute = rejectedExecute;
    const rejected = mount(OrganizationAdminApplication, {
      props: rejectedProps,
      global: {
        stubs: {
          NotificationsDestination: {
            template: `<button id="refresh" @click="$emit('mark-read', { notification_id: 'n-1' })" />`,
          },
        },
      },
    });
    await flushPromises();
    await rejected.get("#refresh").trigger("click");
    await flushPromises();
    expect(rejected.find("#organization-admin-action-error").text()).toContain("forbidden");
    rejected.unmount();
  });
});

function deferred<TResult>() {
  let resolve!: (value: TResult | PromiseLike<TResult>) => void;
  let reject!: (reason?: unknown) => void;
  const promise = new Promise<TResult>((resolvePromise, rejectPromise) => {
    resolve = resolvePromise;
    reject = rejectPromise;
  });
  return { promise, resolve, reject };
}

it("legacy notifications delegate to the canonical account inbox without a second renderer", async () => {
  const surface = required(
    manifest.surfaces.find(({ surfaceId }) => surfaceId === "notifications"),
  );
  const { bridge: query, mock: queryMock } = queryBridgeMock();
  queryMock.mockResolvedValueOnce({ queryVersion: 1, presentation: {} });
  const props = propsFor(surface, query);
  props.context = { ...context, scope: "user", organizationId: null, userId: "user-1" };
  const wrapper = mount(OrganizationAdminApplication, { props });
  await flushPromises();
  expect(wrapper.get("#notifications-destination").attributes("href")).toBe("/notifications");
  expect(wrapper.find("#notifications-panel").exists()).toBe(false);
  expect(queryMock).toHaveBeenCalledTimes(1);
  wrapper.unmount();
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
