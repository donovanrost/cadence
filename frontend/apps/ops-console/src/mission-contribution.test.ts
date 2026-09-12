import { fixtureRecord } from "../../../test-support/json-fixture";
import { fixtureFeaturePort } from "../../../test-support/feature-port";
import { required } from "../../../test-support/required";
import { mount, flushPromises } from "@vue/test-utils";
import { expect, test, vi } from "vite-plus/test";
import type { Component } from "vue";
import type {
  FullPageSurfaceProps,
  HostBridge,
  HostContext,
  HostActionReceipt,
} from "@cadence/plugin-sdk";
import Derived from "./DerivedTelemetryApplication.vue";
import Limits from "./LimitsApplication.vue";
import { manifest as derivedManifest } from "./derived-telemetry";
import { manifest as limitsManifest } from "./limits";

const context: HostContext = {
  scope: "mission",
  organizationId: "organization",
  missionId: "mission-a",
  missionName: "Mission A",
  spacecraftId: null,
  spacecraftName: null,
  actor: { displayName: "Operator", permissions: ["operate_mission"] },
};
const variants = [
  {
    // oxlint-disable-next-line typescript/no-unsafe-assignment -- vue-tsc checks the SFC constructor at this registration or render boundary.
    Component: Derived,
    manifest: derivedManifest,
    feature: "DefinitionsSurface",
    error: "derived-load-error",
  },
  {
    // oxlint-disable-next-line typescript/no-unsafe-assignment -- vue-tsc checks the SFC constructor at this registration or render boundary.
    Component: Limits,
    manifest: limitsManifest,
    feature: "LimitsDefinitionsSurface",
    error: "limits-load-error",
  },
] as const;
function setup(
  variant: (typeof variants)[number],
  surface = required(variant.manifest.surfaces[0]),
) {
  const query = vi
    .fn<HostBridge["query"]>()
    .mockResolvedValue({ trusted_surface: { tag: "current" } });
  const execute = vi
    .fn<HostBridge["execute"]>()
    .mockResolvedValue({ receiptId: "receipt", completedAt: "2026-09-10T00:00:00Z", result: {} });
  const navigate = vi.fn();
  const props: FullPageSurfaceProps = {
    context: { ...context },
    surface,
    application: {
      applicationKey: variant.manifest.application.applicationKey,
      applicationVersion: 1,
      displayName: variant.manifest.application.displayName,
      description: variant.manifest.application.description,
      package: variant.manifest.package,
      surface,
      release: {
        federation: "module_federation",
        releaseId: "ops-console-v1",
        remoteName: "cadence_ops_console",
        manifestUrl: "/assets/application-host/ops-console/mf-manifest.json",
        exposedModule: surface.renderer.exposedModule,
      },
    },
    bridge: {
      // Vitest erases generic call signatures; the feature still admits these unknown fixture responses.
      query: query as HostBridge["query"],
      execute: execute as HostBridge["execute"],
      navigate,
      subscribe: vi.fn(),
    },
  };
  return { props, query, execute, navigate };
}
const stub = (name: string) => ({
  name,
  props: ["document", "port", "hostContext"],
  template: "<span />",
});
const global = {
  stubs: {
    DefinitionsSurface: stub("DefinitionsSurface"),
    LimitsDefinitionsSurface: stub("LimitsDefinitionsSurface"),
    LimitsPostureSurface: stub("LimitsPostureSurface"),
  },
};
function deferred<T = unknown>() {
  let resolve!: (value: T) => void;
  let reject!: (reason: unknown) => void;
  const promise = new Promise<T>((yes, no) => {
    resolve = yes;
    reject = no;
  });
  return { promise, resolve, reject };
}

for (const variant of variants) {
  test.each(["unknown", "toString", "constructor", "__proto__"])(
    `${variant.feature} rejects unsupported surface %s before querying`,
    async (surfaceId) => {
      const c = setup(variant);
      c.props.surface = { ...c.props.surface, surfaceId };
      const wrapper = mount(variant.Component as Component, { props: c.props, global });
      await flushPromises();
      expect(c.query).not.toHaveBeenCalled();
      expect(wrapper.find(`#${variant.error}`).exists()).toBe(true);
      wrapper.unmount();
    },
  );

  test(`${variant.feature} admits compiled identity and mission context before querying`, async () => {
    const changes: ((props: FullPageSurfaceProps) => void)[] = [
      (p) => {
        p.application = { ...p.application, applicationKey: "other" };
      },
      (p) => {
        p.application = { ...p.application, applicationVersion: 2 };
      },
      (p) => {
        p.application = { ...p.application, surface: { ...p.surface, surfaceId: "other" } };
      },
      (p) => {
        p.surface = { ...p.surface, version: 2 };
      },
      (p) => {
        p.surface = { ...p.surface, scope: "organization" };
      },
      (p) => {
        p.surface = { ...p.surface, dataContract: { ...p.surface.dataContract, id: "other" } };
      },
      (p) => {
        p.surface = { ...p.surface, dataContract: { ...p.surface.dataContract, version: 2 } };
      },
      (p) => {
        p.surface = { ...p.surface, actions: [] };
      },
      (p) => {
        p.context = { ...context, missionId: "" };
      },
      (p) => {
        p.context = { ...context, scope: "organization", missionId: null, missionName: null };
      },
    ];
    for (const change of changes) {
      const c = setup(variant);
      change(c.props);
      const wrapper = mount(variant.Component as Component, { props: c.props, global });
      await flushPromises();
      expect(c.query).not.toHaveBeenCalled();
      expect(wrapper.find(`#${variant.error}`).exists()).toBe(true);
      wrapper.unmount();
    }
  });

  test(`${variant.feature} retires ports and reloads a changed mission without applying a late response`, async () => {
    const c = setup(variant),
      late = deferred();
    const wrapper = mount(variant.Component as Component, { props: c.props, global });
    await flushPromises();
    const oldPort = fixtureFeaturePort(
      wrapper.findComponent({ name: variant.feature }).props("port"),
    );
    c.query.mockReturnValueOnce(late.promise);
    const oldRead = oldPort.read();
    const rejected = expect(oldRead).rejects.toThrow("retired");
    const changed = { ...context, missionId: "mission-b", missionName: "Mission B" } as HostContext;
    await wrapper.setProps({ context: changed });
    await flushPromises();
    const next = wrapper.findComponent({ name: variant.feature });
    expect(fixtureRecord(next.props("hostContext")).missionId).toBe("mission-b");
    expect(next.props("port")).not.toBe(oldPort);
    expect(required(c.query.mock.calls.at(-1))[0].context.missionId).toBe("mission-b");
    await expect(oldPort.save({}, "old-key")).rejects.toThrow("retired");
    expect(() => oldPort.navigate("/old")).toThrow("retired");
    expect(c.execute).not.toHaveBeenCalled();
    expect(c.navigate).not.toHaveBeenCalled();
    late.resolve({ trusted_surface: { tag: "old" } });
    await rejected;
    await flushPromises();
    expect(next.props("document")).toEqual({ tag: "current" });
    const port = fixtureFeaturePort(next.props("port"));
    await port.save({}, "same-key");
    expect(required(c.execute.mock.calls[0])[0]).toMatchObject({
      context: { missionId: "mission-b" },
      idempotencyKey: "same-key",
    });
    wrapper.unmount();
    const calls = c.query.mock.calls.length;
    await expect(port.read()).rejects.toThrow("retired");
    await expect(port.save({}, "after-unmount")).rejects.toThrow("retired");
    expect(c.query).toHaveBeenCalledTimes(calls);
    expect(c.execute).toHaveBeenCalledTimes(1);
  });

  test(`${variant.feature} ignores an initial query after the host changes its bridge`, async () => {
    const c = setup(variant),
      old = deferred();
    c.query.mockReturnValueOnce(old.promise);
    const wrapper = mount(variant.Component as Component, { props: c.props, global });
    const nextQuery = vi.fn().mockResolvedValue({ trusted_surface: { tag: "new bridge" } });
    await wrapper.setProps({ bridge: { ...c.props.bridge, query: nextQuery } });
    await flushPromises();
    expect(wrapper.findComponent({ name: variant.feature }).props("document")).toEqual({
      tag: "new bridge",
    });
    old.reject(Error("late failure"));
    await flushPromises();
    expect(wrapper.find(`#${variant.error}`).exists()).toBe(false);
    wrapper.unmount();
  });

  test(`${variant.feature} retries the current query and retires a pending save completion`, async () => {
    const c = setup(variant);
    c.query.mockRejectedValueOnce(Error("read unavailable"));
    const wrapper = mount(variant.Component as Component, { props: c.props, global });
    await flushPromises();
    expect(wrapper.find(`#${variant.error}`).exists()).toBe(true);
    await wrapper.get(`#${variant.error} button`).trigger("click");
    await flushPromises();
    const port = fixtureFeaturePort(wrapper.findComponent({ name: variant.feature }).props("port"));
    const completion = deferred<HostActionReceipt<unknown>>();
    c.execute.mockReturnValueOnce(completion.promise);
    const input = { reviewed: "mission-a" };
    const saving = port.save(input, "exact-save-key");
    const retired = expect(saving).rejects.toThrow("retired");
    expect(required(c.execute.mock.calls[0])[0]).toMatchObject({
      input,
      idempotencyKey: "exact-save-key",
      context: { missionId: "mission-a" },
    });
    await wrapper.setProps({
      context: { ...context, missionId: "mission-b", missionName: "Mission B" },
    });
    await flushPromises();
    completion.resolve({
      receiptId: "old-receipt",
      completedAt: "2026-09-10T00:00:00Z",
      result: {},
    });
    await retired;
    await flushPromises();
    expect(
      fixtureRecord(wrapper.findComponent({ name: variant.feature }).props("hostContext"))
        .missionId,
    ).toBe("mission-b");
    expect(c.execute).toHaveBeenCalledTimes(1);
    expect(c.query).toHaveBeenCalledTimes(3);
    wrapper.unmount();
  });
}

test("Limits changes contributions and does not expose a posture save effect", async () => {
  const variant = variants[1],
    c = setup(variant);
  const wrapper = mount(Limits, { props: c.props, global });
  await flushPromises();
  const oldPort = fixtureFeaturePort(
    wrapper.findComponent({ name: "LimitsDefinitionsSurface" }).props("port"),
  );
  const surface = required(limitsManifest.surfaces[1]);
  await wrapper.setProps({ surface, application: { ...c.props.application, surface } });
  await flushPromises();
  expect(wrapper.findComponent({ name: "LimitsDefinitionsSurface" }).exists()).toBe(false);
  const feature = wrapper.findComponent({ name: "LimitsPostureSurface" });
  expect(feature.exists()).toBe(true);
  expect(required(c.query.mock.calls.at(-1))[0].queryId).toBe("cadence.limits.activity");
  await expect(oldPort.save({}, "old")).rejects.toThrow("retired");
  await expect(fixtureFeaturePort(feature.props("port")).save({}, "posture")).rejects.toThrow(
    "no save action",
  );
  expect(c.execute).not.toHaveBeenCalled();
  wrapper.unmount();
});
