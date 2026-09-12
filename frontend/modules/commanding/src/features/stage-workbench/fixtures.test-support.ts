import { pageFixture, previewFixture } from "../command-authoring/fixtures.test-support";
import type { BatchPreview, Item, ItemPreview, WorkbenchPage } from "./contracts";
export function itemFixture(): Item {
  return {
    id: "item_one",
    expected_item: "d".repeat(64),
    command_id: "command_one",
    revision_id: "model_one",
    target_id: "target_one",
    order: 0,
    state: "draft",
    priority: 3,
    not_before: null,
    expires_at: null,
    request_id: null,
    notes: null,
    available: true,
    argument_values_json: JSON.stringify({ amount: 2, enabled: false }),
  };
}
export function workbenchFixture(selected = false): WorkbenchPage {
  const catalog = pageFixture().catalog,
    item = itemFixture();
  return {
    workbench: {
      version: 2,
      context: catalog.context,
      actor_id: catalog.actor_id,
      mission_name: catalog.mission_name,
      observed_at: catalog.observed_at,
      stage: {
        id: "stage_one",
        expected_stage: "e".repeat(64),
        name: "Flight preparation",
        description: null,
        visibility: "private",
        state: "draft",
        owner_id: catalog.actor_id,
        can_edit_items: true,
        can_edit_stage: true,
      },
      query: { after: "", after_order: "", item: selected ? item.id : "", state: "" },
      items: { limit: 25, entries: [{ ...item, argument_values_json: null }], next_after: null },
      selected_item: selected ? item : null,
    },
    catalog,
    write_token: "c".repeat(64),
    operation: null,
    notice: null,
    item_preview: null,
    batch_preview: null,
  };
}
export function itemPreviewFixture(selected = false): ItemPreview {
  const {
    token: _token,
    request_id: _request,
    lifecycle_state: _state,
    requested_at: _time,
    ...command
  } = previewFixture();
  return {
    token: "f".repeat(64),
    stage_id: "stage_one",
    item_id: selected ? "item_one" : "item_new",
    new: !selected,
    command,
  };
}
export function batchPreviewFixture(): BatchPreview {
  const request = previewFixture();
  return {
    token: request.token,
    stage_id: "stage_one",
    actor_id: request.actor_id,
    requests: [{ ...request, item_id: "item_one", notes: null, order: 0 }],
  };
}
