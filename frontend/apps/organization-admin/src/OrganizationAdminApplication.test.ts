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
import {
  registrationFixture,
  listFixture,
} from "../../../modules/communications/src/features/provider-accounts/provider-accounts.test-support";
import {
  receipt,
  validationReceipt,
} from "../../../modules/communications/src/features/provider-accounts/registration.test-support";
import type { ProviderAccountPayload } from "../../../modules/communications/src/features/provider-accounts/registration.contracts";
import { accountDetailFixture } from "../../../modules/communications/src/features/provider-accounts/detail.test-support";

const context = {
  scope: "organization",
  organizationId: "org-1",
  actor: { displayName: "Mara Vance", permissions: ["applications:view"] },
} as unknown as HostContext;

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
  const mock = vi.fn((request: HostQueryRequest) =>
    Promise.resolve<unknown>({
      queryVersion: 1,
      presentation:
        request.queryId === "cadence.organization.home"
          ? { organization_id: "org-1" }
          : request.queryId === "cadence.organization.provider_accounts.new"
            ? registrationFixture()
            : request.queryId === "cadence.organization.provider_account.show"
              ? accountDetailFixture()
              : request.queryId === "cadence.organization.provider_accounts.list"
                ? listFixture()
                : {},
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

rendererStubs.FederatedNotificationBell = rendererStubs.NotificationsBell!;

afterEach(() => vi.restoreAllMocks());

describe("Organization Admin federated adapter", () => {
  it("legacy directory admits the feature DTO and contains a foreign organization", async () => {
    const surface = manifest.surfaces.find(({ surfaceId }) => surfaceId === "provider_accounts")!;
    const { bridge: query, mock: queryMock } = queryBridgeMock();
    const wrapper = mount(OrganizationAdminApplication, { props: propsFor(surface, query) });
    await flushPromises();
    expect(wrapper.find("#provider-account-account-1").exists()).toBe(true);
    queryMock.mockResolvedValueOnce({
      queryVersion: 1,
      data: { ...listFixture(), organization_id: "foreign" },
    });
    await wrapper.setProps({ context: { ...context } });
    await flushPromises();
    expect(wrapper.find("#organization-admin-error").exists()).toBe(true);
    expect(wrapper.find("#provider-account-account-1").exists()).toBe(false);
    wrapper.unmount();
  });
  it.each(["context", "version", "query"])(
    "rejects incompatible directory %s before querying",
    async (mismatch) => {
      const surface = manifest.surfaces.find(({ surfaceId }) => surfaceId === "provider_accounts")!;
      const { bridge: query, mock: queryMock } = queryBridgeMock();
      const props = propsFor(surface, query);
      if (mismatch === "context") props.context = { ...context, scope: "admin" } as HostContext;
      if (mismatch === "version")
        props.surface = { ...surface, version: 2 } as FullPageSurfaceProps["surface"];
      if (mismatch === "query")
        props.surface = { ...surface, dataContract: { ...surface.dataContract, id: "other" } };
      const wrapper = mount(OrganizationAdminApplication, { props });
      await flushPromises();
      expect(queryMock).not.toHaveBeenCalled();
      expect(wrapper.find("#organization-admin-error").exists()).toBe(true);
      wrapper.unmount();
    },
  );
  it("delegates detail actions with exact account pins and applies patches without remounting", async () => {
    const surface = manifest.surfaces.find(
      ({ surfaceId }) => surfaceId === "provider_account_show",
    )!;
    const { bridge: query, mock: queryMock } = queryBridgeMock();
    const { bridge: execute, mock: executeMock } = actionBridgeMock();
    const next = accountDetailFixture();
    next.account.credential_version = 3;
    executeMock.mockResolvedValueOnce(receipt({ patch: next }));
    const props = propsFor(surface, query);
    props.bridge.execute = execute;
    const wrapper = mount(OrganizationAdminApplication, { props });
    await flushPromises();
    const input = wrapper.get("#grant-grant_reason").element;
    await wrapper.get("#grant-grant_reason").setValue("Keep across rotation");
    await wrapper.get("#rotate-credential").trigger("click");
    await flushPromises();
    expect(executeMock).toHaveBeenCalledExactlyOnceWith({
      applicationKey: "organization_admin",
      applicationVersion: 1,
      surfaceId: "provider_account_show",
      surfaceVersion: 1,
      actionId: "rotate_provider_credential",
      context,
      input: {
        provider_account_id: "account-1",
        expected_account_version: 3,
        credential_ref: "credential-1",
        expected_credential_version: 2,
      },
    });
    expect(queryMock).toHaveBeenCalledTimes(1);
    expect(wrapper.get("#grant-grant_reason").element).toBe(input);
    expect(input).toHaveProperty("value", "Keep across rotation");
    expect(wrapper.find("#provider-account-return").exists()).toBe(false);
    wrapper.unmount();
  });

  it.each(["forbidden", "stale_provider_account", "unknown_failure"])(
    "detail adapter classifies %s without exposing diagnostics",
    async (code) => {
      const surface = manifest.surfaces.find(
        ({ surfaceId }) => surfaceId === "provider_account_show",
      )!;
      const { bridge: query } = queryBridgeMock();
      const { bridge: execute, mock: executeMock } = actionBridgeMock();
      executeMock.mockRejectedValueOnce({
        status: 409,
        code,
        message: "private credential details",
      });
      const props = propsFor(surface, query);
      props.bridge.execute = execute;
      const wrapper = mount(OrganizationAdminApplication, { props });
      await flushPromises();
      await wrapper.get("#rotate-credential").trigger("click");
      await flushPromises();
      expect(wrapper.text()).not.toContain("private credential details");
      expect(wrapper.find("#provider-account-return").exists()).toBe(code === "unknown_failure");
      wrapper.unmount();
    },
  );

  it.each(["organization", "shape"])("contains detail DTOs with invalid %s", async (mismatch) => {
    const surface = manifest.surfaces.find(
      ({ surfaceId }) => surfaceId === "provider_account_show",
    )!;
    const { bridge: query, mock: queryMock } = queryBridgeMock();
    const model = accountDetailFixture();
    model.account.organization_id = "org-foreign";
    queryMock.mockResolvedValueOnce({
      queryVersion: 1,
      presentation: mismatch === "shape" ? {} : model,
    });
    const wrapper = mount(OrganizationAdminApplication, { props: propsFor(surface, query) });
    await flushPromises();
    expect(wrapper.find("#organization-admin-error").exists()).toBe(true);
    expect(wrapper.find("#grant-form").exists()).toBe(false);
    wrapper.unmount();
  });

  it.each(SURFACE_CONTRACTS)(
    "selects $surfaceId, queries its declared DTO, and mounts its legacy component",
    async (contract) => {
      const surface = manifest.surfaces.find(({ surfaceId }) => surfaceId === contract.surfaceId)!;
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
      if (contract.surfaceId === "organization_home") {
        expect(wrapper.get("#organization-home-destination a").attributes("href")).toBe("/");
        expect(wrapper.find("#organization-recent-missions").exists()).toBe(false);
      } else if (contract.surfaceId === "notifications") {
        expect(wrapper.get("#notifications-destination").attributes("href")).toBe("/notifications");
        expect(wrapper.find("#notifications-panel").exists()).toBe(false);
      } else if (
        [
          "admin_home",
          "admin_organizations",
          "admin_organization_new",
          "admin_organization_show",
          "admin_organization_invite",
        ].includes(contract.surfaceId)
      ) {
        const destinations: Record<string, [string, string]> = {
          admin_home: ["platform-overview", "/admin"],
          admin_organizations: ["organization-directory", "/admin/organizations"],
          admin_organization_new: ["organization-create", "/admin/organizations/new"],
          admin_organization_show: ["organization-detail", "/admin/organizations"],
          admin_organization_invite: ["organization-invite", "/admin/organizations"],
        };
        const [id, href] = destinations[contract.surfaceId]!;
        expect(wrapper.get(`#${id}-destination a`).attributes("href")).toBe(href);
        expect(wrapper.find("#org-form").exists()).toBe(false);
      } else {
        expect(wrapper.find(`[data-test-legacy-renderer="${contract.component}"]`).exists()).toBe(
          true,
        );
      }
      wrapper.unmount();
    },
  );

  it("keeps registration mounted while applying validation patches and sends the exact save envelope", async () => {
    const surface = manifest.surfaces.find(
      ({ surfaceId }) => surfaceId === "provider_account_new",
    )!;
    const { bridge: query, mock: queryMock } = queryBridgeMock();
    const { bridge: execute, mock: executeMock } = actionBridgeMock();
    executeMock.mockImplementation(async (request) =>
      request.actionId === "validate_provider_account_form"
        ? validationReceipt((request.input as ProviderAccountPayload).provider_account)
        : receipt({ navigate: "/provider-accounts/account-1" }),
    );
    const props = propsFor(surface, query);
    const navigate = vi.fn();
    props.bridge.execute = execute;
    props.bridge.navigate = navigate;
    const wrapper = mount(OrganizationAdminApplication, { props });
    await flushPromises();
    const input = wrapper.get("#account-display_name").element;
    await wrapper.get("#account-display_name").setValue("Relay Two");
    await flushPromises();
    expect(wrapper.get("#account-display_name").element).toBe(input);
    expect(wrapper.get("#account-display_name").element).toHaveProperty("value", "Relay Two");
    expect(queryMock).toHaveBeenCalledTimes(1);
    expect(executeMock.mock.calls[0][0]).toMatchObject({
      applicationKey: "organization_admin",
      applicationVersion: 1,
      surfaceId: "provider_account_new",
      surfaceVersion: 1,
      actionId: "validate_provider_account_form",
      context,
      input: { provider_account: { provider_account_id: "account-1", display_name: "Relay Two" } },
    });
    await wrapper.get("#registration-form").trigger("submit");
    await flushPromises();
    expect(executeMock.mock.calls[1][0]).toMatchObject({
      applicationKey: "organization_admin",
      applicationVersion: 1,
      surfaceId: "provider_account_new",
      surfaceVersion: 1,
      actionId: "register_provider_account",
      context,
      input: { provider_account: { provider_account_id: "account-1", display_name: "Relay Two" } },
    });
    expect(queryMock).toHaveBeenCalledTimes(1);
    expect(navigate).toHaveBeenCalledExactlyOnceWith("/provider-accounts/account-1");
    wrapper.unmount();
  });

  it("contains malformed registration DTOs and does not display provider error details", async () => {
    const surface = manifest.surfaces.find(
      ({ surfaceId }) => surfaceId === "provider_account_new",
    )!;
    const { bridge: query, mock: queryMock } = queryBridgeMock();
    queryMock.mockResolvedValueOnce({
      queryVersion: 1,
      presentation: { secret: "private detail" },
    });
    const wrapper = mount(OrganizationAdminApplication, { props: propsFor(surface, query) });
    await flushPromises();
    expect(wrapper.find("#organization-admin-error").exists()).toBe(true);
    expect(wrapper.text()).not.toContain("private detail");
    expect(wrapper.find("#registration-form").exists()).toBe(false);
    await wrapper.get("#retry-organization-admin").trigger("click");
    await flushPromises();
    expect(wrapper.find("#registration-form").exists()).toBe(true);
    wrapper.unmount();
  });

  it.each(["invalid_input", "forbidden", "unknown_failure"])(
    "registration adapter classifies action failures conservatively: %s",
    async (code) => {
      const surface = manifest.surfaces.find(
        ({ surfaceId }) => surfaceId === "provider_account_new",
      )!;
      const { bridge: query } = queryBridgeMock();
      const { bridge: execute, mock: executeMock } = actionBridgeMock();
      executeMock.mockImplementation(async (request) => {
        if (request.actionId === "validate_provider_account_form")
          return validationReceipt((request.input as ProviderAccountPayload).provider_account);
        throw { status: 403, code, message: "sensitive backend details" };
      });
      const props = propsFor(surface, query);
      props.bridge.execute = execute;
      const wrapper = mount(OrganizationAdminApplication, { props });
      await flushPromises();
      await wrapper.get("#account-display_name").setValue("Kept");
      await flushPromises();
      await wrapper.get("#registration-form").trigger("submit");
      await flushPromises();
      expect(wrapper.text()).not.toContain("sensitive backend details");
      expect(wrapper.find("#check-provider-account-records").exists()).toBe(
        code === "unknown_failure",
      );
      expect(wrapper.get("#account-display_name").element).toHaveProperty("value", "Kept");
      wrapper.unmount();
    },
  );

  it.each(["context", "version", "query"])(
    "rejects incompatible registration %s before querying",
    async (mismatch) => {
      const surface = manifest.surfaces.find(
        ({ surfaceId }) => surfaceId === "provider_account_new",
      )!;
      const { bridge: query, mock: queryMock } = queryBridgeMock();
      const props = propsFor(surface, query);
      if (mismatch === "context") props.context = { ...context, scope: "admin" } as HostContext;
      if (mismatch === "version")
        props.surface = { ...surface, version: 2 } as FullPageSurfaceProps["surface"];
      if (mismatch === "query")
        props.surface = { ...surface, dataContract: { ...surface.dataContract, id: "other" } };
      const wrapper = mount(OrganizationAdminApplication, { props });
      await flushPromises();
      expect(queryMock).not.toHaveBeenCalled();
      expect(wrapper.find("#organization-admin-error").exists()).toBe(true);
      wrapper.unmount();
    },
  );

  it("rebinds generic action delivery when the adapter context changes", async () => {
    const surface = manifest.surfaces.find(
      ({ surfaceId }) => surfaceId === "admin_organization_invite",
    )!;
    const { bridge: query } = queryBridgeMock();
    const { bridge: execute, mock: executeMock } = actionBridgeMock();
    const props = propsFor(surface, query);
    props.bridge.execute = execute;
    const wrapper = mount(OrganizationAdminApplication, {
      props,
      global: {
        stubs: {
          OrganizationInviteDestination: {
            template:
              '<button id="context-action" @click="$emit(\'validate\', { invite: {} })">Validate</button>',
          },
        },
      },
    });
    await flushPromises();
    const nextContext = { ...context, organizationId: "org-2" } as HostContext;
    await wrapper.setProps({ context: nextContext });
    await flushPromises();
    await wrapper.get("#context-action").trigger("click");
    await flushPromises();
    expect(executeMock).toHaveBeenCalledExactlyOnceWith(
      expect.objectContaining({ context: nextContext }),
    );
    wrapper.unmount();
  });

  it("honors same-origin navigation receipts without issuing a redundant query", async () => {
    const surface = manifest.surfaces.find(
      ({ surfaceId }) => surfaceId === "admin_organization_show",
    )!;
    const { bridge: query, mock: queryMock } = queryBridgeMock();
    const { bridge: execute, mock: executeMock } = actionBridgeMock();
    executeMock.mockResolvedValue({
      receiptId: "receipt-navigation-1",
      completedAt: "2026-09-04T00:00:01Z",
      result: { navigation: { href: "/session/organization" } },
    });
    const props = propsFor(surface, query);
    props.bridge.execute = execute;
    const assign = vi.spyOn(window.location, "assign").mockImplementation(() => undefined);
    const wrapper = mount(OrganizationAdminApplication, {
      props,
      global: {
        stubs: {
          OrganizationDetailDestination: {
            template: `<button id="issue" @click="$emit('issue-service-identity', { service_identity: { display_name: 'Relay', service_identity_id: 'svc-1' } })" />`,
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
    const surface = manifest.surfaces.find(({ surfaceId }) => surfaceId === "admin_runtime")!;
    const { bridge: query, mock: queryMock } = queryBridgeMock();
    const first = deferred<Awaited<ReturnType<HostBridge["execute"]>>>();
    const second = deferred<Awaited<ReturnType<HostBridge["execute"]>>>();
    const { bridge: execute, mock: executeMock } = actionBridgeMock();
    executeMock.mockReturnValueOnce(first.promise).mockReturnValueOnce(second.promise);
    const props = propsFor(surface, query);
    props.bridge.execute = execute;
    const wrapper = mount(OrganizationAdminApplication, {
      props,
      global: {
        stubs: {
          AdminRuntime: {
            template: `<button id="refresh" @click="$emit('refresh')" />`,
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
    rejectedProps.bridge.execute = rejectedExecute;
    const rejected = mount(OrganizationAdminApplication, {
      props: rejectedProps,
      global: {
        stubs: { AdminRuntime: { template: `<button id="refresh" @click="$emit('refresh')" />` } },
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
  const surface = manifest.surfaces.find(({ surfaceId }) => surfaceId === "notifications")!;
  const { bridge: query, mock: queryMock } = queryBridgeMock();
  queryMock.mockResolvedValueOnce({ queryVersion: 1, presentation: {} });
  const props = propsFor(surface, query);
  props.context = { ...context, scope: "user", userId: "user-1" } as unknown as HostContext;
  const wrapper = mount(OrganizationAdminApplication, { props });
  await flushPromises();
  expect(wrapper.get("#notifications-destination").attributes("href")).toBe("/notifications");
  expect(wrapper.find("#notifications-panel").exists()).toBe(false);
  expect(queryMock).toHaveBeenCalledTimes(1);
  wrapper.unmount();
});

it("the legacy bell validates its host recipient and navigates without a duplicate read action", async () => {
  const surface = manifest.surfaces.find(({ surfaceId }) => surfaceId === "notifications_bell")!;
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
