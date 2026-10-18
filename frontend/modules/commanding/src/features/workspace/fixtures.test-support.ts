import { pageFixture, previewFixture } from "../command-authoring/fixtures.test-support";
import { workbenchFixture } from "../stage-workbench/fixtures.test-support";
import { monitorFixture } from "../mission-commands/monitor.test-support";
import type { TargetsPreview, WorkspacePreparation } from "./contracts";
import type { QueuePreview } from "./queue-contracts";

export function queuePreviewFixture(draft = targetsPreviewFixture()): QueuePreview {
  return {
    token: "8".repeat(64),
    actor_id: draft.actor_id,
    requests: draft.items.map((item, index) => ({
      ...previewFixture(),
      ...item.command,
      request_id: `request_direct_${index}`,
    })),
  };
}

export function workspaceFixture(): WorkspacePreparation {
  const catalog = pageFixture().catalog;
  const workbench = workbenchFixture().workbench;
  const monitor = monitorFixture();
  return {
    state: "prepare",
    initial_shelf: "expanded",
    catalog,
    workbench,
    directory: {
      version: 1,
      context: catalog.context,
      actor_id: catalog.actor_id,
      mission_name: catalog.mission_name,
      observed_at: catalog.observed_at,
      query: { after: "", state: "", query: "" },
      stages: {
        limit: 25,
        entries: [
          {
            id: workbench.stage.id,
            name: workbench.stage.name,
            visibility: "private",
            state: "draft",
            owner_id: catalog.actor_id,
          },
        ],
        next_after: null,
      },
    },
    spacecraft: [{ id: "craft_one", name: "KESTREL-01" }],
    new_stage_id: "stage_reserved",
    write_token: "c".repeat(64),
    operation: null,
    draft_preview: null,
    queue_preview: null,
    batch_preview: null,
    monitor: {
      ...monitor,
      organization_id: catalog.context.organizationId,
      mission_id: catalog.context.missionId,
    },
  };
}
export function targetsPreviewFixture(): TargetsPreview {
  const preview = previewFixture();
  const {
    token: _token,
    request_id: _id,
    requested_at: _time,
    lifecycle_state: _state,
    ...command
  } = preview;
  return {
    token: "d".repeat(64),
    stage_id: "stage_one",
    actor_id: "user_one",
    notes: null,
    items: [
      {
        token: "e".repeat(64),
        stage_id: "stage_one",
        item_id: "item_reserved",
        new: true,
        order: 1,
        command,
      },
    ],
  };
}
