import { flushPromises, mount } from "@vue/test-utils";
import { afterEach, describe, expect, it } from "vite-plus/test";
import { decode, type ApiError } from "@/api";
import { settingsReader, type SettingsField } from "./api.ts";
import {
  approvalRefusal,
  canInherit,
  disabledValues,
  inheritHint,
  lockedLine,
  onlyPin,
  optionsHint,
  pinnable,
  readOnly,
  readOnlyHint,
} from "./governance.ts";
import MissionSettingsField from "./MissionSettingsField.vue";

/** The mission's approval setting as #233's read sends it (api; ux U96), decoded. */
function approval(extra: Readonly<Record<string, unknown>>, value: unknown = "direct") {
  const r = decode(settingsReader, {
    sections: [
      {
        key: "cadence.governance",
        title: "Governance",
        purpose: null,
        locked: false,
        version: null,
        fields: [
          {
            path: "approval_requirement",
            label: "Approval",
            type: "enum",
            unit: null,
            enum: [
              { value: "direct", label: "Applies without approval" },
              { value: "independent", label: "Needs a second person's approval" },
            ],
            range: null,
            default: "independent",
            required: false,
            help: null,
            visible_when: null,
            value,
            source: "mission",
            inherited_value: "independent",
            ...extra,
          },
        ],
      },
    ],
    permissions: ["settings.edit"],
  });
  if (!r.ok) throw new Error(JSON.stringify(r.error));
  const f = r.value.sections[0]?.fields[0];
  if (!f) throw new Error("fixture");
  return f;
}
const refused = (code: string): ApiError => ({ kind: "forbidden", code, message: "Forbidden" });

describe("#233 limits, read from allowed_values and can_inherit (ux U96)", () => {
  it("reads both keys, and absent keys limit nothing (fields that aren't governed)", () => {
    const f = approval({});
    expect([f.allowed_values, f.can_inherit]).toEqual([undefined, undefined]);
    expect([readOnly(f), canInherit(f), disabledValues([f])]).toEqual([false, true, {}]);
    expect([readOnlyHint(f), optionsHint(f), inheritHint(f, "EARENDIL")]).toEqual([
      null,
      null,
      null,
    ]);
  });
  it("a mission admin may only tighten: Applies without approval is shown disabled", () => {
    const f = approval({ allowed_values: ["independent"], can_inherit: true });
    expect(disabledValues([f])).toEqual({ approval_requirement: ["direct"] });
    expect(optionsHint(f)).toBe(
      "Only an organization admin can let changes apply without approval.",
    );
    expect(readOnly(f)).toBe(false);
  });
  it("picks the read-only line by the current value, since the read carries no role", () => {
    expect(readOnlyHint(approval({ allowed_values: [] }, "direct"))).toBe(
      "Only a mission admin or an organization admin can change this.",
    );
    expect(readOnlyHint(approval({ allowed_values: [] }, "independent"))).toBe(
      "It's already set to the strictest option. Only an organization admin can loosen it.",
    );
    expect(disabledValues([approval({ allowed_values: [] })])).toEqual({});
  });
  it("says why the organization's setting can't be chosen when can_inherit is false", () => {
    const f = approval({ allowed_values: [], can_inherit: false }, "independent");
    expect(canInherit(f)).toBe(false);
    expect(inheritHint(f, "EARENDIL")).toBe(
      "The organization's setting lets changes apply without approval, so only an organization admin can switch EARENDIL to it.",
    );
  });
  it("words a refused save by the level it saved; anything else falls through", () => {
    const org = refused("approval_policy_change_requires_organization_admin");
    expect(approvalRefusal(org, "mission", "cadence.governance", "EARENDIL")).toBe(
      "Not saved: only an organization admin can let changes on EARENDIL apply without approval.",
    );
    expect(approvalRefusal(org, "organization", "cadence.governance", "EARENDIL")).toBe(
      "Not saved: only an organization admin can change the organization's approval setting.",
    );
    // A mission admin's save at the organization level is a plain 403.
    expect(approvalRefusal(refused("forbidden"), "organization", "cadence.governance", "x")).toBe(
      "Not saved: only an organization admin can change the organization's approval setting.",
    );
    expect(
      approvalRefusal(
        refused("approval_policy_change_requires_mission_admin"),
        "mission",
        "cadence.governance",
        "EARENDIL",
      ),
    ).toBe(
      "Not saved: only a mission admin or an organization admin can change approval settings.",
    );
    expect(approvalRefusal(refused("forbidden"), "organization", "cadence.alarms", "x")).toBeNull();
    const stale: ApiError = {
      kind: "conflict",
      code: "version_conflict",
      message: "Stale",
      details: null,
    };
    expect(approvalRefusal(stale, "mission", "cadence.governance", "EARENDIL")).toBeNull();
  });
  it("gives the governance section its own locked line", () => {
    expect(lockedLine("cadence.governance")).toBe(
      "The organization sets this for every mission, and missions can't change it. An organization admin changes it in the organization's settings.",
    );
    expect(lockedLine("cadence.alarms")).toBe(
      "The organization sets these and doesn't allow missions to override them.",
    );
  });
});

let wrapper: ReturnType<typeof mount> | null = null;
const mountField = (field: SettingsField, explain = true) => {
  wrapper = mount(MissionSettingsField, {
    props: {
      field,
      canChange: true,
      busy: false,
      confirmReset: false,
      orgName: "Reflect Orbital",
      missionName: "EARENDIL",
      explain,
    },
    attachTo: document.body,
  });
  return wrapper;
};
afterEach(() => {
  wrapper?.unmount();
  wrapper = null;
});
const buttons = (w: ReturnType<typeof mount>) => w.findAll("button").map((b) => b.text());

describe("a mission's approval setting, per #233 limits (ux U96 A6)", () => {
  it("read-only: no Change, and the line says why", () => {
    const w = mountField(approval({ allowed_values: [], can_inherit: true }, "independent"));
    expect(buttons(w)).toEqual(["Reset to inherited"]);
    expect(w.text()).toContain("It's already set to the strictest option.");
  });
  it("Reset stays but is disabled with ux's reason when can_inherit is false", async () => {
    const w = mountField(approval({ allowed_values: [], can_inherit: false }, "independent"));
    // A disabled ApButton's text includes its screen-reader reason.
    const reset = w.findAll("button").find((b) => b.text().startsWith("Reset to inherited"));
    // ApButton's disabled-reason pattern: aria-disabled, the reason as its title, a click does nothing.
    expect(reset?.attributes("aria-disabled")).toBe("true");
    expect(reset?.attributes("title")).toContain("only an organization admin can switch EARENDIL");
    await reset?.trigger("click");
    expect(w.emitted("reset")).toBeUndefined();
    expect(w.text()).toContain("so only an organization admin can switch EARENDIL to it.");
  });
  it("Change shows the looser option disabled, its reason in the select's own hint", async () => {
    const w = mountField(approval({ allowed_values: ["independent"], can_inherit: true }));
    await w
      .findAll("button")
      .find((b) => b.text() === "Change")
      ?.trigger("click");
    await flushPromises();
    const options = w.findAll("option").filter((o) => o.attributes("value") !== "");
    expect(
      options.map((o) => [o.attributes("value"), o.attributes("disabled") !== undefined]),
    ).toEqual([
      ["direct", true],
      ["independent", false],
    ]);
    // A6: the reason is announced with the control, through the select's aria-describedby.
    const described = (w.get("select").attributes("aria-describedby") ?? "")
      .split(" ")
      .map((id) => document.getElementById(id)?.textContent ?? "")
      .join(" ");
    expect(described).toContain(
      "Only an organization admin can let changes apply without approval.",
    );
  });
  it("keeps a current value that's now disabled shown and selected while editing", async () => {
    const w = mountField(
      approval({ allowed_values: ["independent"], can_inherit: true }, "direct"),
    );
    await w
      .findAll("button")
      .find((b) => b.text() === "Change")
      ?.trigger("click");
    await flushPromises();
    const select = w.get("select").element;
    if (!(select instanceof HTMLSelectElement)) throw new Error("no select");
    expect(select.value).toBe("direct");
    expect(select.selectedOptions[0]?.disabled).toBe(true);
    await w
      .findAll("button")
      .find((b) => b.text() === "Save")
      ?.trigger("click");
    expect(w.emitted("unchanged")).toHaveLength(1);
    expect(w.emitted("save")).toBeUndefined();
  });
  it("explains nothing in a locked section (its callout does)", () => {
    const w = mountField(approval({ allowed_values: [], can_inherit: false }, "direct"), false);
    expect(w.text()).not.toContain("Only a mission admin");
  });
});

describe("Set for <mission>: keep the organization's value (ux U96 pin)", () => {
  /** A mission inheriting independent, as api reads it to a mission admin: allowed [independent]. */
  const inherited = (allowed: readonly unknown[]) =>
    approval({ source: "organization", allowed_values: allowed, can_inherit: true }, "independent");
  it("offers it only for an inherited value this viewer may set", () => {
    expect([pinnable(inherited(["independent"])), onlyPin(inherited(["independent"]))]).toEqual([
      true,
      true,
    ]);
    // An organization admin may also choose another value, so Override stays.
    expect(onlyPin(inherited(["direct", "independent"]))).toBe(false);
    expect(pinnable(inherited([]))).toBe(false);
    expect(pinnable(approval({ allowed_values: ["independent"] }, "independent"))).toBe(false);
    expect(pinnable(approval({ source: "organization" }, "independent"))).toBe(false);
  });
  it("sets the inherited value for the mission, with ux's line, in place of Override", async () => {
    const w = mountField(inherited(["independent"]));
    expect(buttons(w)).toEqual(["Set for EARENDIL"]);
    expect(w.text()).toContain(
      "EARENDIL uses the organization's setting. Set it for EARENDIL to keep it if the organization's setting changes.",
    );
    await w
      .findAll("button")
      .find((b) => b.text() === "Set for EARENDIL")
      ?.trigger("click");
    expect(w.emitted("save")).toEqual([[{ approval_requirement: "independent" }]]);
  });
  it("keeps Override beside it when the viewer may choose more", () => {
    expect(buttons(mountField(inherited(["direct", "independent"])))).toEqual([
      "Set for EARENDIL",
      "Override",
    ]);
  });
});
