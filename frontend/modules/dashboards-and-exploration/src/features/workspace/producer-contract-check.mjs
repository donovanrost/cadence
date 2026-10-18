import { fixtureRows, fixtureString } from "../../../../../test-support/json-fixture.ts";
import assert from "node:assert/strict";
import { readWorkspaceSnapshot } from "./validation.ts";
import { snapshotPresentation } from "./snapshot-presentation.ts";
for (const raw of fixtureRows(process.argv[2])) {
  const context = {
    organizationId: fixtureString(raw.organization_id),
    missionId: fixtureString(raw.mission_id),
    resourceId: fixtureString(raw.dashboard_id),
  };
  const model = readWorkspaceSnapshot(raw, context);
  assert.equal(model, raw);
  assert.throws(() => readWorkspaceSnapshot(model, { ...context, resourceId: "other-dashboard" }));
  assert.throws(() => readWorkspaceSnapshot({ ...model, version: 2 }, context));
  const presentation = snapshotPresentation(model, "producer-test");
  const widgets = presentation.groups.flatMap((group) => group.grid.widgets);
  assert.equal(widgets.length, model.placements.length);
  for (const placement of model.placements) {
    const rendered = widgets.find((widget) => widget.key === placement.id);
    assert.ok(rendered);
    if (placement.status === "ready") {
      assert.ok(placement.widget);
      assert.equal(rendered.presentation.body.content?.presentation.kind, placement.widget.type);
      if (placement.widget.type === "time_series") {
        const content = rendered.presentation.body.content;
        assert.ok(content && content.presentation.kind === "time_series");
        const chart = content.presentation.chart.props;
        assert.equal(chart.legend_mode, placement.widget.options.legend_mode);
        assert.equal(chart.line_width, placement.widget.options.line_width);
        assert.equal(chart.fill_opacity, placement.widget.options.fill_opacity);
      }
    } else {
      assert.equal(rendered.presentation.body.content, null);
      assert.ok(rendered.presentation.body.notice);
      assert.match(rendered.presentation.body.notice.text, /unavailable/);
    }
  }
}
console.log("Workspace producer/consumer contract passed.");
