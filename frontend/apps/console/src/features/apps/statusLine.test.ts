import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import AppStatusLine from "./AppStatusLine.vue";
import type { AppStatus } from "./host.ts";

describe("the app frame's status line (ux #77; a11y B6)", () => {
  const active: AppStatus = {
    state: "active",
    label: null,
    activation_request: null,
    version: "3",
  };
  const pending: AppStatus = {
    ...active,
    state: "activation_pending",
    activation_request: {
      requested_by: { kind: "user", id: "u-mira", name: "Mira K." },
      requested_at: "2026-11-19T21:10:00Z",
    },
  };

  it("keeps its status region mounted and empty while nothing waits", () => {
    expect(
      mount(AppStatusLine, { props: { status: active } })
        .get("[role=status]")
        .text(),
    ).toBe("");
  });

  it("names the pending request's requester and time", () => {
    const w = mount(AppStatusLine, { props: { status: pending } });
    expect(w.get("[role=status]").text()).toMatch(
      /^Waiting for activation approval · requested by Mira K\. at /,
    );
  });
});
