import { expect, test } from "vite-plus/test";
import { opsNavigation } from "./navigation";
import { contextSections } from "./context";
import { context } from "../../../auth-and-navigation/shared/context.test-support";
test("capabilities determine available navigation and active links", () => {
  const admin = { ...context, capabilities: ["organization_admin"] };
  expect(
    opsNavigation(admin)
      .groups.find((group) => group.key === "act")
      .items.map((item) => item.key),
  ).toEqual(["commands", "activations"]);
  const nav = opsNavigation({
    ...admin,
    ops_context: { pinned_focus: { kind: "command", id: "cmd/a?b" } },
  });
  expect(nav.groups[1].items[0].href).toBe(
    "/missions/mission%2F1/ops/commands?focus_command_id=cmd%2Fa%3Fb",
  );
  expect(nav.groups[1].items[0].active).toBe(true);
});
test("operational context preserves unavailable data, severity and command focus", () => {
  const sections = contextSections({
    ...context,
    ops_context: {
      pinned_focus: { kind: "command", id: "cmd-1" },
      modules: [
        {
          key: "fleet_health",
          status: null,
          count: null,
          freshness: "unavailable",
          observed_at: "2026-09-05T12:00:00Z",
          data: null,
        },
        {
          key: "alarms",
          status: "critical",
          count: 2,
          freshness: "current",
          observed_at: "2026-09-05T12:00:00Z",
          data: { active_count: 2, critical_count: 2 },
        },
      ],
    },
  });
  expect(sections[0].content.available).toBe(false);
  expect(sections[0].observed_at_label).toBe("12:00:00 UTC");
  expect(sections[1].content.badges[0]).toMatchObject({ count: 2, label: "Critical" });
  expect(sections[1].destination).toBe("/missions/mission%2F1/ops/alarms?focus_command_id=cmd-1");
});
