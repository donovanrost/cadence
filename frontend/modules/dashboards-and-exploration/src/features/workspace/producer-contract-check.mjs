import assert from "node:assert/strict";
import { readWorkspaceSnapshot } from "./validation.ts";
import { snapshotPresentation } from "./snapshot-presentation.ts";
for (const model of JSON.parse(process.argv[2])) {
  const context = {
    organizationId: model.organization_id,
    missionId: model.mission_id,
    resourceId: model.dashboard_id,
  };
  assert.equal(readWorkspaceSnapshot(model, context), model);
  assert.throws(() => readWorkspaceSnapshot(model, { ...context, resourceId: "other-dashboard" }));
  assert.throws(() => readWorkspaceSnapshot({ ...model, version: 2 }, context));
  const presentation = snapshotPresentation(model, "producer-test");
  const widgets = presentation.groups.flatMap((group) => group.grid.widgets);
  assert.equal(widgets.length, model.placements.length);
  for (const placement of model.placements) {
    const rendered = widgets.find((widget) => widget.key === placement.id);
    assert.ok(rendered);
    if (placement.status === "ready") {
      assert.equal(rendered.presentation.body.content?.presentation.kind, placement.widget.type);
      if (placement.widget.type === "time_series") {
        const chart = rendered.presentation.body.content.presentation.chart.props;
        assert.equal(chart.legend_mode, placement.widget.options.legend_mode);
        assert.equal(chart.line_width, placement.widget.options.line_width);
        assert.equal(chart.fill_opacity, placement.widget.options.fill_opacity);
      }
    } else {
      assert.equal(rendered.presentation.body.content, null);
      assert.match(rendered.presentation.body.notice.text, /unavailable/);
    }
  }
}
console.log("Workspace producer/consumer contract passed.");
