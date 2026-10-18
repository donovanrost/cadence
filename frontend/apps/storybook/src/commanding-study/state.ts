import { computed, reactive, ref } from "vue";
import {
  commands,
  fleet,
  type Command,
  type CommandId,
  type Draft,
  type Execution,
  type StagedItem,
} from "./fixtures";

export function useCommandingStudy() {
  const selectedIds = ref<string[]>([]);
  const selected = computed(() => fleet.filter((target) => selectedIds.value.includes(target.id)));
  const command = ref<Command | null>(null);
  const drafts = reactive<Record<CommandId, Draft>>({
    NOOP: { value: "", overrides: {} },
    SET_TLM_RATE: { value: "5 s", overrides: {} },
    SET_ATTITUDE: { value: "Sun pointing", overrides: {} },
    CAPTURE_IMAGE: { value: "25 ms", overrides: {} },
    RESET_COMPUTER: { value: "", overrides: {} },
  });
  const draft = computed(() => drafts[command.value?.id ?? "NOOP"]);
  const incompatible = computed(() => {
    const current = command.value;
    return current ? selected.value.filter((target) => !target.supports.includes(current.id)) : [];
  });
  const canStage = computed(
    () => !!command.value && selected.value.length > 0 && incompatible.value.length === 0,
  );
  const staged = ref<StagedItem[]>([]);
  const execution = ref<Execution[]>([]);
  const shelf = ref<"stage" | "execution">("stage");
  const shelfOpen = ref(false);
  const reviewing = ref(false);
  const confirmed = ref(false);
  const feedback = ref("");
  let nextId = 1;

  function toggleTarget(id: string) {
    if (!fleet.some((target) => target.id === id)) return;
    selectedIds.value = selectedIds.value.includes(id)
      ? selectedIds.value.filter((value) => value !== id)
      : [...selectedIds.value, id];
  }
  function chooseCommand(id: CommandId) {
    command.value = commands.find((item) => item.id === id) ?? null;
  }
  function setValue(value: string) {
    if (command.value?.choices.includes(value)) draft.value.value = value;
  }
  function setOverride(id: string, value: string) {
    if (value === "") delete draft.value.overrides[id];
    else if (command.value?.choices.includes(value)) draft.value.overrides[id] = value;
  }
  function stage() {
    const current = command.value;
    if (!current || !canStage.value) return;
    const additions = selected.value.map((target) => ({
      id: nextId++,
      target,
      command: current,
      value: draft.value.overrides[target.id] ?? draft.value.value,
    }));
    staged.value = [...staged.value, ...additions];
    reviewing.value = false;
    confirmed.value = false;
    shelf.value = "stage";
    shelfOpen.value = true;
    feedback.value = "Staged " + current.id + " for " + additions.length + " spacecraft.";
  }
  function remove(id: number) {
    staged.value = staged.value.filter((item) => item.id !== id);
    reviewing.value = false;
    confirmed.value = false;
  }
  function move(id: number, offset: number) {
    const items = [...staged.value];
    const index = items.findIndex((item) => item.id === id);
    const destination = index + offset;
    if (index < 0 || destination < 0 || destination >= items.length) return;
    const [item] = items.splice(index, 1);
    if (!item) return;
    items.splice(destination, 0, item);
    staged.value = items;
    reviewing.value = false;
    confirmed.value = false;
  }
  function review() {
    if (!staged.value.length) return;
    reviewing.value = true;
    confirmed.value = false;
  }
  function releaseSimulation() {
    if (!reviewing.value || !confirmed.value || !staged.value.length) return;
    execution.value = [
      ...execution.value,
      ...staged.value.map((item): Execution => ({
        ...item,
        status: item.command.hazardous
          ? "Awaiting approval"
          : item.target.contact
            ? "Queued"
            : "Waiting for contact",
      })),
    ];
    feedback.value =
      "Moved " + staged.value.length + " commands into the simulated execution queue.";
    staged.value = [];
    reviewing.value = false;
    confirmed.value = false;
    shelf.value = "execution";
  }
  function advanceSimulation() {
    execution.value = execution.value.map((item) => ({
      ...item,
      status:
        item.status === "Queued"
          ? "Awaiting verification"
          : item.status === "Awaiting verification"
            ? "Verified"
            : item.status,
    }));
  }
  return {
    selectedIds,
    selected,
    command,
    draft,
    incompatible,
    canStage,
    staged,
    execution,
    shelf,
    shelfOpen,
    reviewing,
    confirmed,
    feedback,
    toggleTarget,
    chooseCommand,
    setValue,
    setOverride,
    stage,
    remove,
    move,
    review,
    releaseSimulation,
    advanceSimulation,
  };
}
