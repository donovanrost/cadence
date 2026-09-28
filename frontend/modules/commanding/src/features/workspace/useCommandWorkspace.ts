import { computed, onBeforeUnmount, ref, shallowRef, watch } from "vue";
import type { OpsPagePort, LiveOpsPageReadPort } from "@cadence/plugin-sdk/ops-pages";
import { useWorkspaceRequests } from "./useWorkspaceRequests";
import { useCatalogResults } from "./useCatalogResults";
import { useLiveWorkspaceRead } from "./useLiveWorkspaceRead";
import { readQueuePreview, type QueuePreview } from "./queue-contracts";
import {
  emptyCatalogQuery,
  readBatchPreview,
  type Item,
  type ItemPreview,
  type WorkbenchQuery,
  type BatchPreview,
} from "@cadence/commanding/stage-workbench";
import type { StageQuery } from "@cadence/commanding/command-stages";
import {
  previewInput,
  targetBasis,
  type Query,
  type Target,
} from "../../shared/command-draft/contracts";
import type { ArgumentEditorDraft } from "../../shared/command-draft/argument-editor";
import {
  parseArgumentValues,
  scalarInputText,
  sameArgumentValues,
} from "../../shared/command-draft/exact-values";
import { record, text } from "../../shared/stages/validation";
import {
  readTargetsPreview,
  readWorkspace,
  readWorkspaceOperation,
  type TargetsPreview,
  type WorkspaceOperation,
  type WorkspacePreparation,
  type WorkspaceObservation,
  type WriteEvent,
} from "./contracts";

export type WorkspaceDraft = {
  valueMode: "shared" | "individual";
  arguments: ArgumentEditorDraft | undefined;
  overrides: Record<string, ArgumentEditorDraft>;
  priority: string;
  notBefore: string;
  expiresAt: string;
  notes: string;
};
export const emptyWorkspaceDraft = (): WorkspaceDraft => ({
  valueMode: "shared",
  arguments: undefined,
  overrides: {},
  priority: "3",
  notBefore: "",
  expiresAt: "",
  notes: "",
});
export type TargetIntent = { target: Target; arguments: string };
type CommandInput = ReturnType<typeof previewInput>;

export function useCommandWorkspace(
  initial: WorkspacePreparation,
  port: OpsPagePort,
  readPort: LiveOpsPageReadPort,
  observe: (page: WorkspaceObservation) => void,
) {
  const page = shallowRef(initial),
    submitting = ref(false),
    browsing = ref(false),
    reviewing = ref(false),
    feedback = ref(""),
    accessLost = ref(false);
  const context = { ...initial.directory.context },
    actor = initial.directory.actor_id;
  const writeToken = ref(initial.write_token),
    operation = shallowRef<WorkspaceOperation | null>(initial.operation);
  const dismissedEnqueue = ref<string | null>(null);
  const enqueueResult = computed(() => {
    const result = operation.value;
    return result?.event === "enqueue" &&
      (result.status === "unconfirmed" || result.write_token !== dismissedEnqueue.value)
      ? result
      : null;
  });
  const targetPreview = shallowRef<TargetsPreview | null>(initial.draft_preview),
    queuePreview = shallowRef<QueuePreview | null>(initial.queue_preview),
    batchPreview = shallowRef(initial.batch_preview);
  const selection = shallowRef<readonly Target[]>(
    initial.queue_preview?.requests.map((request) => request.target) ??
      initial.draft_preview?.items.map((item) => item.command.target) ??
      (initial.catalog?.target_bases && initial.catalog.selected_target
        ? [initial.catalog.selected_target]
        : []),
  );
  const itemSelection = shallowRef<Readonly<Record<string, string>>>({});
  const confirmed = ref(false),
    dockOpen = ref(initial.initial_shelf === "expanded" || !!initial.workbench);
  const drafts = shallowRef<Readonly<Record<string, WorkspaceDraft>>>(restoreDraft(initial));
  const command = computed(() => page.value.catalog?.selected_command ?? null);
  const draft = computed(() =>
    command.value
      ? (drafts.value[command.value.id] ?? emptyWorkspaceDraft())
      : emptyWorkspaceDraft(),
  );
  const writesDisabled = computed(
    () => accessLost.value || submitting.value || browsing.value || !writeToken.value,
  );
  const requests = useWorkspaceRequests(port);
  let browseGeneration = 0;
  const browseRequests = new Map<unknown, number>();
  let reviewGeneration = 0;
  const names = shallowRef<Readonly<Record<string, string>>>(
    Object.fromEntries(initial.spacecraft.map((row) => [row.id, row.name])),
  );
  let attemptedItem: string | undefined;
  let attemptedTargets = initial.draft_preview;
  let attemptedBatch = initial.batch_preview;
  let attemptedQueue = initial.queue_preview;
  let disposed = false;
  const validating = ref(false);
  const validationEpoch = ref(0);
  let validationGeneration = 0;
  let validationSuspended = false;
  let pendingValidation: (() => Promise<void>) | null = null;
  let activeValidation: Promise<void> | null = null;
  function invalidateValidation() {
    validationGeneration++;
    pendingValidation = null;
    targetPreview.value = null;
    queuePreview.value = null;
  }
  async function drainValidation() {
    if (activeValidation || browsing.value || disposed) return;
    validating.value = true;
    activeValidation = (async () => {
      while (pendingValidation && !browsing.value && !disposed) {
        const validate = pendingValidation;
        pendingValidation = null;
        await validate();
      }
    })();
    try {
      await activeValidation;
    } finally {
      activeValidation = null;
      validating.value = false;
    }
  }
  watch(browsing, (value) => {
    if (!value && pendingValidation) void drainValidation();
  });
  onBeforeUnmount(() => {
    disposed = true;
    invalidateValidation();
  });

  function edited() {
    validationSuspended = false;
    if (operation.value?.event === "enqueue" && operation.value.status !== "unconfirmed")
      dismissedEnqueue.value = operation.value.write_token;
    invalidateValidation();
    feedback.value = "";
  }
  function setDraft(value: WorkspaceDraft) {
    if (accessLost.value || !command.value) return;
    drafts.value = { ...drafts.value, [command.value.id]: value };
    edited();
  }
  async function select(target: Target) {
    if (accessLost.value) return;
    const selected = selection.value.some((item) => item.id === target.id);
    if (!selected && selection.value.length === 25) {
      feedback.value = "Prepare up to 25 targets at a time.";
      return;
    }
    selection.value = selected
      ? selection.value.filter((item) => item.id !== target.id)
      : [...selection.value, target];
    edited();
    if (
      page.value.catalog?.target_bases &&
      selection.value[0] &&
      page.value.catalog.query.target !== selection.value[0].id
    )
      await browseCatalog({ target: selection.value[0].id, command: "" });
  }
  function selectVisible() {
    if (accessLost.value) return;
    const next = new Map(selection.value.map((target) => [target.id, target]));
    for (const target of targetResults.state.value.entries.slice(0, 25))
      next.set(target.id, target);
    if (next.size > 25) {
      feedback.value = "This would exceed 25 selected targets. Clear some targets first.";
      return;
    }
    selection.value = [...next.values()];
    edited();
  }
  function clearSelection() {
    if (!accessLost.value) {
      selection.value = [];
      edited();
    }
  }
  function receive(value: unknown) {
    const next = readWorkspace(value, context);
    if (next.state !== "prepare") {
      invalidateValidation();
      accessLost.value = true;
      observe(next);
      return;
    }
    if (next.directory.actor_id !== actor) throw Error("Changed actor");
    if (
      operation.value?.status === "unconfirmed" &&
      next.operation?.write_token !== operation.value.write_token
    )
      throw Error("Missing write receipt");
    if (operation.value?.status === "unconfirmed" && next.operation) {
      checkReceipt(
        next.operation,
        operation.value,
        attemptedTargets,
        attemptedBatch,
        attemptedItem,
        attemptedQueue,
      );
    }
    const sameStage = page.value.workbench?.stage.id === next.workbench?.stage.id;
    const selected = Object.fromEntries(
      Object.entries(itemSelection.value).filter(
        ([id, token]) =>
          sameStage &&
          next.workbench?.items.entries.some(
            (item) =>
              item.id === id &&
              item.expected_item === token &&
              item.state === "draft" &&
              item.available,
          ),
      ),
    );
    const lostSelection = Object.keys(selected).length !== Object.keys(itemSelection.value).length;
    const lostReview =
      batchPreview.value !== null &&
      (!sameStage || lostSelection || batchPreview.value.token !== next.batch_preview?.token);
    const ownWrite =
      next.operation?.status === "completed" &&
      next.operation.write_token !== page.value.operation?.write_token;
    page.value = next;
    accessLost.value = false;
    operation.value = next.operation;
    writeToken.value = next.write_token;
    const previewInvalidated =
      (targetPreview.value && targetPreview.value.token !== next.draft_preview?.token) ||
      (queuePreview.value && queuePreview.value.token !== next.queue_preview?.token);
    if (previewInvalidated) validationEpoch.value++;
    // A read cannot restore a preview invalidated by local edits or selection changes.
    if (targetPreview.value?.token !== next.draft_preview?.token) targetPreview.value = null;
    if (queuePreview.value?.token !== next.queue_preview?.token) queuePreview.value = null;
    if (lostReview) {
      batchPreview.value = null;
      confirmed.value = false;
      if (!ownWrite)
        feedback.value =
          "The selected draft evidence changed. Review the current stage before submitting.";
    }
    itemSelection.value = selected;
    names.value = {
      ...names.value,
      ...Object.fromEntries(next.spacecraft.map((row) => [row.id, row.name])),
    };
  }
  const { refresh, syncing, syncFailed } = useLiveWorkspaceRead(
    readPort,
    computed(() => requests.pending.value > 0 || validating.value || browsing.value),
    receive,
  );
  const catalogOptions = {
    catalog: computed(() => page.value.catalog),
    blocked: accessLost,
    port,
    context,
    actor,
    onSpacecraft(rows: readonly { id: string; name: string }[]) {
      names.value = {
        ...names.value,
        ...Object.fromEntries(rows.map((row) => [row.id, row.name])),
      };
    },
    onStale: refresh,
  };
  const targetResults = useCatalogResults({
    ...catalogOptions,
    queryKey: "target_query",
    afterKey: "target_after",
    pick: (catalog) => catalog.targets,
  });
  const commandResults = useCatalogResults({
    ...catalogOptions,
    queryKey: "command_query",
    afterKey: "command_after",
    pick: (catalog) => catalog.commands,
  });
  async function browse(input: Record<string, unknown>) {
    if (accessLost.value || disposed) return;
    const generation = ++browseGeneration;
    browseRequests.set(input.kind, generation);
    browsing.value = true;
    reviewGeneration++;
    reviewing.value = false;
    edited();
    confirmed.value = false;
    if (input.kind === "stage" || input.kind === "items") {
      batchPreview.value = null;
      itemSelection.value = {};
    }
    try {
      const value = await requests.execute(
        "browse",
        input,
        () => browseRequests.get(input.kind) === generation,
      );
      if (disposed || generation !== browseGeneration) return;
      if (record(value) && value.status === "rejected" && text(value.feedback)) {
        feedback.value = value.feedback;
        return;
      }
      if (!record(value) || value.status !== "browsed") throw Error("Invalid workspace view");
      receive(value.data);
    } catch {
      if (!disposed && generation === browseGeneration)
        feedback.value =
          "This view could not be loaded. Your preparation is still here; try opening it again.";
    } finally {
      if (!disposed && generation === browseGeneration) browsing.value = false;
    }
  }
  const browseCatalog = (query: Partial<Query>) =>
    browse({
      kind: "catalog",
      query: { ...(page.value.catalog?.query ?? emptyCatalogQuery()), ...query },
    });
  async function chooseStage(id: string) {
    await browse({ kind: "stage", id });
    if (!disposed && page.value.workbench?.stage.id === id) dockOpen.value = true;
  }
  const browseItems = (query: Partial<WorkbenchQuery>) =>
    browse({ kind: "items", query: { ...page.value.workbench?.query, ...query } });
  const browseStages = (query: Partial<StageQuery>) =>
    browse({ kind: "stages", query: { ...page.value.directory.query, ...query } });

  function prepare(intents: readonly TargetIntent[] | null) {
    if (validationSuspended) return;
    invalidateValidation();
    feedback.value = "";
    const catalog = page.value.catalog,
      workbench = page.value.workbench;
    if (accessLost.value || browsing.value || !catalog || !intents?.length) return;
    if (intents.some((entry) => !targetBasis(catalog, entry.target.id)?.compatible)) {
      feedback.value =
        "The selected command differs between these spacecraft catalogs or is unavailable. Prepare those spacecraft separately.";
      return;
    }
    let inputs: CommandInput[];
    try {
      if (
        intents.length !== selection.value.length ||
        intents.some((entry, index) => entry.target.id !== selection.value[index]?.id)
      )
        throw Error("Targets changed");
      inputs = intents.map((entry) =>
        previewInput(
          { ...catalog, selected_target: entry.target },
          entry.arguments,
          draft.value.priority,
          draft.value.notBefore,
          draft.value.expiresAt,
        ),
      );
      if (!text(draft.value.notes, 4000))
        throw Error("Draft notes must fit within 4,000 UTF-8 bytes.");
    } catch {
      feedback.value = "Check the selected targets, arguments, notes and UTC timing.";
      return;
    }
    const notes = draft.value.notes || null;
    const generation = validationGeneration;
    pendingValidation = async () => {
      try {
        const value = await requests.execute(
          "preview_targets",
          {
            expected_stage: workbench?.stage.can_edit_items ? workbench.stage.expected_stage : null,
            commands: inputs,
            notes,
          },
          () => generation === validationGeneration,
        );
        if (disposed || generation !== validationGeneration) return;
        if (record(value) && value.status === "rejected" && text(value.feedback)) {
          feedback.value = value.feedback;
          return;
        }
        if (!record(value) || value.status !== "previewed") throw Error();
        const queue = readQueuePreview(value.queue_preview, actor);
        if (
          queue.requests.length !== inputs.length ||
          queue.requests.some(
            (request, index) =>
              !matchesIntent(
                request,
                inputs[index],
                intents[index]?.target,
                targetBasis(catalog, request.target.id)?.revision_id,
              ),
          )
        )
          throw Error("Preview differs from preparation");
        if (value.preview !== null) {
          if (!workbench) throw Error("Unexpected stage preview");
          const preview = readTargetsPreview(value.preview, actor, workbench.stage.id);
          if (
            preview.notes !== notes ||
            preview.items.length !== inputs.length ||
            preview.items.some(
              (item, index) =>
                !matchesIntent(
                  item.command,
                  inputs[index],
                  intents[index]?.target,
                  targetBasis(catalog, item.command.target.id)?.revision_id,
                ),
            )
          )
            throw Error("Stage preview differs from preparation");
          targetPreview.value = preview;
        }
        queuePreview.value = queue;
      } catch {
        if (!disposed && generation === validationGeneration)
          feedback.value = "Validation could not be completed. Check your connection and retry.";
      }
    };
    void drainValidation();
  }
  function chooseItem(item: Item) {
    if (accessLost.value || item.state !== "draft" || !item.available) return;
    const next = { ...itemSelection.value };
    if (next[item.id]) delete next[item.id];
    else next[item.id] = item.expected_item;
    itemSelection.value = next;
    reviewGeneration++;
    reviewing.value = false;
    batchPreview.value = null;
    confirmed.value = false;
  }
  async function reviewBatch() {
    const workbench = page.value.workbench,
      selected = { ...itemSelection.value };
    if (
      accessLost.value ||
      browsing.value ||
      reviewing.value ||
      !workbench ||
      !Object.keys(selected).length
    )
      return;
    const generation = ++reviewGeneration;
    reviewing.value = true;
    feedback.value = "";
    batchPreview.value = null;
    confirmed.value = false;
    try {
      const value = await requests.execute(
        "preview_batch",
        {
          expected_stage: workbench.stage.expected_stage,
          items: Object.entries(selected).map(([id, expected_item]) => ({ id, expected_item })),
        },
        () => generation === reviewGeneration,
      );
      if (disposed || generation !== reviewGeneration) return;
      if (record(value) && value.status === "rejected" && text(value.feedback)) {
        feedback.value = value.feedback;
        return;
      }
      if (!record(value) || value.status !== "previewed") throw Error();
      const preview = readBatchPreview(value.preview, actor, workbench.stage.id);
      if (
        preview.requests.length !== Object.keys(selected).length ||
        preview.requests.some((request) => !Object.hasOwn(selected, request.item_id))
      )
        throw Error();
      batchPreview.value = preview;
    } catch {
      if (!disposed && generation === reviewGeneration)
        feedback.value =
          "The request preview could not be confirmed. Select the current drafts and review again.";
    } finally {
      if (!disposed && generation === reviewGeneration) reviewing.value = false;
    }
  }
  async function write(event: WriteEvent, input: Record<string, unknown>) {
    if (writesDisabled.value || !writeToken.value) return;
    const token = writeToken.value,
      targets = targetPreview.value,
      queue = queuePreview.value,
      batch = batchPreview.value;
    const stage =
      event === "create_stage" ? page.value.new_stage_id : page.value.workbench?.stage.id;
    if (event !== "enqueue" && !stage) return;
    submitting.value = true;
    validationSuspended = event === "enqueue" || event === "save_targets";
    invalidateValidation();
    feedback.value = "";
    writeToken.value = null;
    if (event === "enqueue") {
      operation.value = { status: "unconfirmed", event, stage_id: null, write_token: token };
    } else {
      if (!stage) return;
      operation.value = { status: "unconfirmed", event, stage_id: stage, write_token: token };
    }
    const attempt = operation.value;
    attemptedItem = typeof input.item_id === "string" ? input.item_id : undefined;
    attemptedTargets = targets;
    attemptedBatch = batch;
    attemptedQueue = queue;
    if (event !== "enqueue") dockOpen.value = true;
    let known = false;
    try {
      const value = await requests.execute(event, { ...input, expected_write: token });
      if (disposed) return;
      // A bare rejection can only deny this attempt; it cannot restore a consumed write token.
      if (
        record(value) &&
        value.status === "rejected" &&
        value.write_token === undefined &&
        text(value.feedback)
      ) {
        feedback.value = value.feedback;
        return;
      }
      const result = readWorkspaceOperation(value, actor);
      checkReceipt(result, attempt, targets, batch, attemptedItem, queue);
      operation.value = result;
      known = true;
    } catch {
      if (!disposed && event !== "enqueue")
        feedback.value =
          "The write result is unconfirmed. Use Check result to inspect the saved outcome.";
    } finally {
      if (!disposed) submitting.value = false;
    }
    if (!disposed && known) await refresh();
  }
  const saveTargets = () =>
    !validating.value && targetPreview.value
      ? write("save_targets", { expected_preview: targetPreview.value.token })
      : Promise.resolve();
  const enqueue = () =>
    !validating.value && queuePreview.value
      ? write("enqueue", { expected_preview: queuePreview.value.token })
      : Promise.resolve();
  const submit = () =>
    confirmed.value && batchPreview.value
      ? write("submit", { expected_preview: batchPreview.value.token })
      : Promise.resolve();
  const createStage = (name: string, visibility: "private" | "shared") =>
    write("create_stage", { name, visibility, description: null });
  function cancelItem(item: Item) {
    return write("cancel_item", {
      item_id: item.id,
      expected_item: item.expected_item,
      expected_stage: page.value.workbench?.stage.expected_stage,
    });
  }
  function moveItem(item: Item, order: number) {
    return write("edit_details", {
      item_id: item.id,
      expected_item: item.expected_item,
      expected_stage: page.value.workbench?.stage.expected_stage,
      notes: item.notes,
      order,
    });
  }
  function follow(event: MouseEvent, href: string) {
    if (event.button || event.metaKey || event.ctrlKey || event.altKey || event.shiftKey) return;
    event.preventDefault();
    port.navigate(href);
  }
  return {
    page,
    context,
    submitting,
    browsing,
    reviewing,
    validating,
    validationEpoch,
    syncing,
    syncFailed,
    writesDisabled,
    feedback,
    accessLost,
    operation,
    enqueueResult,
    command,
    draft,
    names,
    selection,
    itemSelection,
    targetPreview,
    queuePreview,
    batchPreview,
    confirmed,
    dockOpen,
    setDraft,
    select,
    selectVisible,
    clearSelection,
    browseCatalog,
    targetResults: targetResults.state,
    commandResults: commandResults.state,
    searchTargets: targetResults.search,
    searchCommands: commandResults.search,
    loadMoreTargets: targetResults.loadMore,
    loadMoreCommands: commandResults.loadMore,
    retryTargets: targetResults.retry,
    retryCommands: commandResults.retry,
    browseItems,
    browseStages,
    chooseStage,
    prepare,
    chooseItem,
    reviewBatch,
    saveTargets,
    enqueue,
    submit,
    createStage,
    cancelItem,
    moveItem,
    refresh,
    follow,
  };
}

function checkReceipt(
  result: WorkspaceOperation,
  attempt: WorkspaceOperation,
  targets: TargetsPreview | null,
  batch: BatchPreview | null,
  itemId: string | undefined,
  queue: QueuePreview | null,
) {
  if (
    result.write_token !== attempt.write_token ||
    result.event !== attempt.event ||
    result.stage_id !== attempt.stage_id
  )
    throw Error("Changed write identity");
  if (result.status !== "completed") return;
  const receipt = result.receipt;
  if (
    receipt.kind === "enqueue" &&
    (!queue ||
      receipt.requests.length !== queue.requests.length ||
      receipt.requests.some((request, index) => {
        const preview = queue.requests[index];
        return (
          !preview ||
          request.request_id !== preview.request_id ||
          request.target_id !== preview.target.id ||
          request.requested_at !== preview.requested_at ||
          request.state !==
            (preview.lifecycle_state === "validated" ? "queued" : "approval_pending")
        );
      }))
  )
    throw Error("Changed queue receipt");
  if (
    receipt.kind === "drafts" &&
    JSON.stringify(receipt.items.map((item) => item.item_id)) !==
      JSON.stringify(targets?.items.map((item) => item.item_id))
  )
    throw Error("Changed draft receipt");
  if (
    receipt.kind === "requests" &&
    JSON.stringify(receipt.requests.map((r) => [r.request_id, r.item_id, r.requested_at])) !==
      JSON.stringify(batch?.requests.map((r) => [r.request_id, r.item_id, r.requested_at]))
  )
    throw Error("Changed request receipt");
  if (receipt.kind === "item" && receipt.item_id !== itemId) throw Error("Changed item receipt");
}

function matchesIntent(
  command: ItemPreview["command"],
  input: CommandInput | undefined,
  target: Target | undefined,
  revision: string | undefined,
) {
  return (
    !!input &&
    !!target &&
    command.target.spacecraft_id === target.spacecraft_id &&
    command.target.scid === target.scid &&
    command.target.source_ref === target.source_ref &&
    command.target.id === input.source_endpoint_ref &&
    command.command_id === input.command_id &&
    command.revision_id === revision &&
    sameArgumentValues(command.argument_values_json, input.argument_values_json) &&
    command.priority === input.priority &&
    sameTime(command.not_before, input.not_before) &&
    sameTime(command.expires_at, input.expires_at)
  );
}
const normalizeUtc = (value: string) => {
  const [whole, fraction = ""] = value.slice(0, -1).split(".");
  return `${whole}.${fraction.padEnd(6, "0")}Z`;
};
const sameTime = (left: string | null, right: string | null) =>
  left === right || (left !== null && right !== null && normalizeUtc(left) === normalizeUtc(right));

function restoreDraft(page: WorkspacePreparation): Readonly<Record<string, WorkspaceDraft>> {
  const command = page.catalog?.selected_command;
  const requests =
    page.queue_preview?.requests ?? page.draft_preview?.items.map((item) => item.command) ?? [];
  const first = requests[0];
  if (!command || !first || requests.some((request) => request.command_id !== command.id))
    return {};
  const overrides = Object.fromEntries(
    requests.map((request) => {
      const values = parseArgumentValues(request.argument_values_json);
      return [
        request.target.id,
        {
          values: Object.fromEntries(
            command.arguments.flatMap((argument) => {
              const value = values[argument.name];
              if (argument.fixed_value_json !== null || value === undefined) return [];
              return [
                [argument.name, argument.type === "enumerated" ? value : scalarInputText(value)],
              ];
            }),
          ),
        },
      ];
    }),
  );
  return {
    [command.id]: {
      ...emptyWorkspaceDraft(),
      valueMode: requests.length > 1 ? "individual" : "shared",
      arguments: overrides[first.target.id],
      overrides,
      priority: String(first.priority),
      notBefore: first.not_before ?? "",
      expiresAt: first.expires_at ?? "",
      notes: page.draft_preview?.notes ?? "",
    },
  };
}
