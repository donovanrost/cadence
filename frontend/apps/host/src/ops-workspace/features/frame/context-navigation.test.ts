import assert from "node:assert/strict";
import { expect, test } from "vite-plus/test";
import { opsNavigation } from "./navigation";
import { contextSections } from "./context";
import { required } from "../../../../../../test-support/required";
import { readOpsFrameContext } from "./context-contract";
import { context } from "../../../auth-and-navigation/shared/context.test-support";
test("operators see every workspace group without a built-in role and links are plain paths", () => {
  const nav = opsNavigation(required(readOpsFrameContext({ ...context, capabilities: [] })));
  expect(nav.groups.map((group) => group.key)).toEqual(["observe", "system"]);
  const dashboards = required(
    required(nav.groups[0]).items.find((item) => item.key === "dashboards"),
  );
  expect(dashboards.href).toBe("/missions/mission%2F1/ops/dashboards");
  expect(dashboards.active).toBe(true);
});
test("operational context preserves unavailable data and severity", () => {
  const sections = contextSections(
    required(
      readOpsFrameContext({
        ...context,
        ops_context: {
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
      }),
    ),
  );
  const health = required(sections[0]),
    alarms = required(sections[1]);
  assert.ok(health.content.kind === "fleet_health");
  assert.ok(alarms.content.kind === "alarms");
  expect(health.content.available).toBe(false);
  expect(health.observed_at_label).toBe("12:00:00 UTC");
  expect(alarms.content.badges[0]).toMatchObject({ count: 2, label: "Critical" });
  expect(alarms.destination).toBeNull();
});
