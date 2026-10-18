import { computed, onBeforeUnmount, ref, shallowRef } from "vue";
import type { OpsPagePort, OpsPageReadPort } from "@cadence/plugin-sdk/ops-pages";
import { readWriteResult, type Operation } from "../../shared/stages/operations";
import { record, text } from "../../shared/stages/validation";
import {
  emptyCatalogQuery,
  readBatchPreview,
  readItemPreview,
  readWorkbenchPage,
  workbenchHref,
  type BatchPreview,
  type ItemPreview,
  type WorkbenchPage,
  type WorkbenchQuery,
} from "./contracts";
import type { Query } from "../../shared/command-draft/contracts";
export function useStageWorkbench(
  initial: WorkbenchPage,
  port: OpsPagePort,
  readPort: OpsPageReadPort,
) {
  const page = shallowRef(initial),
    workbench = computed(() => page.value.workbench),
    context = { ...initial.workbench.context },
    actor = initial.workbench.actor_id,
    stageId = initial.workbench.stage.id;
  const busy = ref(false),
    reading = ref(false),
    feedback = ref(""),
    operation = shallowRef<Operation | null>(initial.operation),
    writeToken = ref(initial.write_token);
  const itemPreview = shallowRef<ItemPreview | null>(initial.item_preview),
    batchPreview = shallowRef<BatchPreview | null>(initial.batch_preview);
  const selection = shallowRef<Record<string, string>>({}),
    batchConfirmed = ref(false);
  const locked = computed(() => busy.value || reading.value || !writeToken.value);
  let disposed = false;
  const unguard = port.guardNavigation?.(() => !busy.value && !reading.value);
  onBeforeUnmount(() => {
    disposed = true;
    unguard?.();
  });
  function href(changes: Partial<WorkbenchQuery> = {}, catalogChanges: Partial<Query> = {}) {
    return workbenchHref(
      context.missionId,
      stageId,
      { ...workbench.value.query, ...changes },
      { ...(page.value.catalog?.query ?? emptyCatalogQuery()), ...catalogChanges },
    );
  }
  function follow(event: MouseEvent, url: string) {
    if (
      event.button === 0 &&
      !event.metaKey &&
      !event.ctrlKey &&
      !event.shiftKey &&
      !event.altKey
    ) {
      event.preventDefault();
      if (!busy.value && !reading.value) port.navigate(url);
    }
  }
  function choose(id: string, checked: boolean) {
    if (locked.value) return;
    const item = workbench.value.items.entries.find((x) => x.id === id);
    if (!item || item.state !== "draft" || !item.available) return;
    const next = { ...selection.value };
    if (checked) next[id] = item.expected_item;
    else delete next[id];
    selection.value = next;
    batchPreview.value = null;
    batchConfirmed.value = false;
  }
  function clearItemPreview() {
    itemPreview.value = null;
    feedback.value = "";
  }
  async function refresh() {
    if (busy.value || reading.value) return;
    reading.value = true;
    feedback.value = "";
    try {
      const next = readWorkbenchPage(await readPort.read(), context);
      if (next.workbench.actor_id !== actor || next.workbench.stage.id !== stageId) throw Error();
      if (
        operation.value?.status === "unconfirmed" &&
        (!next.operation || next.operation.write_token !== operation.value.write_token)
      )
        throw Error();
      if (disposed) return;
      page.value = next;
      operation.value = next.operation;
      writeToken.value = next.write_token;
      itemPreview.value = next.item_preview;
      batchPreview.value = next.batch_preview;
      batchConfirmed.value = false;
      selection.value = {};
    } catch {
      if (!disposed)
        feedback.value =
          "The stage could not be refreshed. Check the result again before making another change.";
    } finally {
      if (!disposed) reading.value = false;
    }
  }
  async function previewItem(input: Record<string, unknown>) {
    if (locked.value) return;
    busy.value = true;
    itemPreview.value = null;
    feedback.value = "";
    try {
      const result = await port.execute("preview_item", input);
      if (disposed) return;
      if (record(result) && result.status === "rejected" && text(result.feedback)) {
        feedback.value = result.feedback;
        return;
      }
      if (!record(result) || result.status !== "previewed") throw Error();
      itemPreview.value = readItemPreview(
        result.preview,
        actor,
        stageId,
        page.value.catalog,
        workbench.value.selected_item,
      );
    } catch {
      if (!disposed)
        feedback.value = "The draft preview could not be confirmed. Refresh and review it again.";
    } finally {
      if (!disposed) busy.value = false;
    }
  }
  async function previewBatch() {
    if (locked.value || !Object.keys(selection.value).length) return;
    busy.value = true;
    feedback.value = "";
    batchPreview.value = null;
    batchConfirmed.value = false;
    const items = Object.entries(selection.value).map(([id, expected_item]) => ({
      id,
      expected_item,
    }));
    try {
      const result = await port.execute("preview_batch", {
        expected_stage: workbench.value.stage.expected_stage,
        items,
      });
      if (disposed) return;
      if (record(result) && result.status === "rejected" && text(result.feedback)) {
        feedback.value = result.feedback;
        return;
      }
      if (!record(result) || result.status !== "previewed") throw Error();
      const preview = readBatchPreview(result.preview, actor, stageId);
      if (
        preview.requests.length !== items.length ||
        preview.requests.some((r) => !Object.hasOwn(selection.value, r.item_id))
      )
        throw Error();
      batchPreview.value = preview;
    } catch {
      if (!disposed)
        feedback.value =
          "The selected batch could not be confirmed. Refresh and review the current drafts.";
    } finally {
      if (!disposed) busy.value = false;
    }
  }
  async function write(event: string, fields: Record<string, unknown>) {
    if (locked.value || !writeToken.value) return;
    const token = writeToken.value,
      capturedItem = itemPreview.value?.item_id ?? workbench.value.selected_item?.id,
      capturedBatch = batchPreview.value;
    busy.value = true;
    feedback.value = "";
    writeToken.value = null;
    operation.value = { status: "unconfirmed", event, write_token: token };
    let known = false;
    try {
      const result = readWriteResult(
        await port.execute(event, { ...fields, expected_write: token }),
        actor,
        stageId,
        token,
        event,
      );
      if (disposed) return;
      if (result.status === "completed") {
        if (
          ["save_item", "edit_details", "cancel_item"].includes(event) &&
          result.receipt.item_id !== capturedItem
        )
          throw Error();
        if (
          event === "submit" &&
          (!capturedBatch ||
            JSON.stringify(
              result.receipt.requests?.map((r) => [r.request_id, r.item_id, r.requested_at]),
            ) !==
              JSON.stringify(
                capturedBatch.requests.map((r) => [r.request_id, r.item_id, r.requested_at]),
              ))
        )
          throw Error();
      }
      if ("write_token" in result) operation.value = result;
      else {
        operation.value = null;
        feedback.value = result.feedback;
      }
      known = true;
    } catch {
      if (!disposed)
        feedback.value =
          "The write result is unconfirmed. Refresh to check it without repeating the action.";
    } finally {
      if (!disposed) busy.value = false;
    }
    if (!disposed && known) await refresh();
  }
  async function saveItem(notes: string, order: number) {
    if (!itemPreview.value) return;
    const input: Record<string, unknown> = {
      expected_stage: workbench.value.stage.expected_stage,
      expected_preview: itemPreview.value.token,
      notes: notes || null,
      order,
    };
    if (!itemPreview.value.new) input.expected_item = workbench.value.selected_item?.expected_item;
    await write("save_item", input);
  }
  async function submit() {
    if (batchConfirmed.value && batchPreview.value)
      await write("submit", { expected_preview: batchPreview.value.token });
  }
  async function restartDraft() {
    const previous = operation.value;
    if (
      busy.value ||
      reading.value ||
      previous?.status !== "unconfirmed" ||
      previous.event === "submit"
    )
      return;
    busy.value = true;
    try {
      const result = await port.execute("restart_draft", { expected_write: previous.write_token });
      if (!record(result) || result.status !== "reset" || !text(result.notice)) throw Error();
      if (!disposed) operation.value = null;
    } catch {
      if (!disposed) feedback.value = "The previous write still needs to be checked.";
    } finally {
      if (!disposed) busy.value = false;
    }
    if (!disposed && !operation.value) await refresh();
  }
  return {
    page,
    workbench,
    context,
    actor,
    stageId,
    busy,
    reading,
    feedback,
    operation,
    writeToken,
    itemPreview,
    batchPreview,
    selection,
    batchConfirmed,
    locked,
    href,
    follow,
    choose,
    clearItemPreview,
    refresh,
    previewItem,
    previewBatch,
    write,
    saveItem,
    submit,
    restartDraft,
  };
}
