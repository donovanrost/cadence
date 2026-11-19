import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import AppStatusLine from "./AppStatusLine.vue";
import AppSurfaceNotice from "./AppSurfaceNotice.vue";
import type { AppStatus } from "./host.ts";

/** #313 A3 (ux §10): a requested activation reads one line, the caution status line (B6). */
const WAITING = "Waiting for activation approval";
const requested = { kind: "activation_requested", text: "x" } as const;
const notice = {
  appName: "Decom",
  missionName: "QA",
  refusal: null,
  noSurface: false,
  readOnly: false,
};
const active: AppStatus = { state: "active", label: null, activation_request: null, version: "3" };

describe("A3: one line for a requested activation", () => {
  it("drops the nominal 'Activation requested…' callout; other saves keep theirs", () => {
    expect(mount(AppSurfaceNotice, { props: { ...notice, outcome: requested } }).text()).toBe("");
    const saved = { kind: "saved", text: "Saved. It applies now." } as const;
    expect(mount(AppSurfaceNotice, { props: { ...notice, outcome: saved } }).text()).toBe(
      "Saved. It applies now.",
    );
  });

  it("says it in the status line, as a status region, as soon as it's requested", async () => {
    const w = mount(AppStatusLine, { props: { appKey: "telemetry_decom", status: active } });
    const region = w.get("[role=status]");
    expect(region.text()).toBe("");
    await w.setProps({ requested: true });
    expect(w.get("[role=status]").text()).toBe(WAITING);
  });

  it("gives way to the status's own line once the status is read", () => {
    const pending: AppStatus = {
      ...active,
      state: "activation_pending",
      activation_request: { requested_by: null, requested_at: "2026-11-19T21:10:00Z" },
    };
    const w = mount(AppStatusLine, {
      props: { appKey: "telemetry_decom", status: pending, requested: true },
    });
    expect(w.findAll("[role=status]")).toHaveLength(1);
    expect(w.get("[role=status]").text()).toMatch(
      /^Waiting for activation approval · requested at /,
    );
  });
});
