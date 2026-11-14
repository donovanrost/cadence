<script setup lang="ts">
import { computed, nextTick, onMounted, useTemplateRef } from "vue";
import { ApCallout, ApSegmented, ApTag } from "@/ui";
import type { FleetSpacecraft } from "@/features/fleet/index.ts";
import { argInput } from "../args.ts";
import ArgField from "./ArgField.vue";
import PerTargetPanel from "./PerTargetPanel.vue";
import type { VerifierGroup } from "../groups/api.ts";
import { verifiersDiffer } from "../groups/verifierGroups.ts";
import VerifierGroups from "../groups/VerifierGroups.vue";
import { checkItem, setPerTargetMode, verifierLine, type StackItem } from "./stack.ts";

/** Inline form for one stack row: every argument from the catalog, errors inline. */
const props = defineProps<{
  item: StackItem;
  targets: readonly FleetSpacecraft[];
  /** U51: how each group of targets verifies this command (preflight); [] before it answers. */
  groups?: readonly VerifierGroup[] | undefined;
  nameOf?: ((spacecraftId: string) => string) | undefined;
}>();
const differ = computed(() => verifiersDiffer(props.groups ?? []));
const emit = defineEmits<{
  change: [values: Record<string, string>];
  perTarget: [perTarget: StackItem["perTarget"]];
  done: [];
}>();
const root = useTemplateRef<HTMLFormElement>("root");
/** Canvas fix #13: the form opens with focus on the first argument; ↵ confirms (closes the row). */
onMounted(() => {
  void nextTick(() =>
    root.value?.querySelector<HTMLElement>("input, select, textarea, [role=radio]")?.focus(),
  );
});
const check = computed(() =>
  checkItem(
    props.item,
    props.targets.map((t) => t.id),
  ),
);
/** B2: numbers can differ per target (CommandFlow.md C1 `Same for all │ Per target`). */
const perTargetable = (argId: string) => {
  const arg = props.item.command.arguments.find((a) => a.id === argId);
  return arg !== undefined && argInput(arg).kind === "number";
};
const MODES = [
  { value: "all", label: "Same for all" },
  { value: "per", label: "Per target" },
] as const;
const anyPerTarget = computed(() => Object.keys(props.item.perTarget).length > 0);
const verifier = computed(() => verifierLine(props.item.command));
/**
 * ↵ closes the row only when every value checks (ux Compose ruling #1). Otherwise the form stays
 * open and focus goes to the first invalid field, so nothing is left at NEEDS VALUES unseen.
 */
function submit() {
  if (check.value.ok) {
    emit("done");
    return;
  }
  void nextTick(() =>
    (
      root.value?.querySelector<HTMLElement>("[aria-invalid='true']") ??
      root.value?.querySelector<HTMLElement>("input, select, textarea, [role=radio]")
    )?.focus(),
  );
}
const set = (argId: string, value: string) =>
  emit("change", { ...props.item.values, [argId]: value });
</script>

<template>
  <form
    ref="root"
    class="flex flex-col gap-3 border-t border-hairline-faint bg-vacuum/40 px-4 py-3"
    @submit.prevent="submit"
  >
    <button type="submit" class="sr-only">Done</button>
    <!-- U51: when targets verify it differently, one row per verifier set replaces the line. -->
    <div v-if="differ" class="flex flex-col gap-1">
      <ApTag state="caution" label="Verifiers differ" class="self-start" />
      <VerifierGroups :groups="groups ?? []" :name-of="nameOf ?? ((id) => id)" />
    </div>
    <p
      v-else
      class="m-0 font-mono text-xs uppercase"
      :class="verifier.verifiable ? 'text-text-2' : 'text-stale-text'"
    >
      {{ verifier.text }}
    </p>
    <p
      v-if="item.command.arguments.length === 0"
      class="m-0 font-mono text-xs text-text-4 uppercase"
    >
      No arguments
    </p>
    <div class="grid grid-cols-1 gap-3 md:grid-cols-2">
      <div v-for="arg in item.command.arguments" :key="arg.id" class="flex flex-col gap-1">
        <ArgField
          :arg="arg"
          :error="check.errors[arg.id] ?? null"
          :model-value="item.values[arg.id] ?? ''"
          @update:model-value="(v) => set(arg.id, v)"
        />
        <ApSegmented
          v-if="perTargetable(arg.id)"
          :model-value="arg.id in item.perTarget ? 'per' : 'all'"
          :options="MODES"
          :label="`${arg.name} values`"
          variant="micro"
          @update:model-value="
            (v) => emit('perTarget', setPerTargetMode(item, arg.id, v === 'per'))
          "
        />
      </div>
    </div>
    <PerTargetPanel
      v-if="anyPerTarget"
      :item="item"
      :targets="targets"
      @change="(p) => emit('perTarget', p)"
    />
    <ApCallout v-if="check.hazardousValues.length" tone="caution">
      The catalog marks the value of {{ check.hazardousValues.join(", ") }} as hazardous.
    </ApCallout>
  </form>
</template>
