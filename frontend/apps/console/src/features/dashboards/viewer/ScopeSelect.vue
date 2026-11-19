<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted } from "vue";
import { ApSelect, type ApSelectOption } from "@/ui";

/**
 * Spacecraft scope for context-bound widgets (`?spacecraft=`). `[` / `]` step to the previous /
 * next spacecraft (ux), unless focus is in a text field; not on phones (`keys: false`).
 */
const props = withDefaults(
  defineProps<{ options: readonly { id: string; name: string }[]; keys?: boolean | undefined }>(),
  { keys: true },
);
const model = defineModel<string>({ required: true });
const DEFAULT = "";
const choices = computed<ApSelectOption<string>[]>(() => [
  { value: DEFAULT, label: "Dashboard default" },
  ...props.options.map((o) => ({ value: o.id, label: o.name })),
]);

function step(direction: -1 | 1) {
  const ids = props.options.map((o) => o.id);
  if (ids.length === 0) return;
  const at = ids.indexOf(model.value);
  const next =
    at < 0 ? (direction === 1 ? 0 : ids.length - 1) : (at + direction + ids.length) % ids.length;
  model.value = ids[next] ?? DEFAULT;
}
function onKey(event: KeyboardEvent) {
  if (!props.keys) return;
  const target = event.target;
  if (target instanceof HTMLElement && target.closest("input, textarea, select, [contenteditable]"))
    return;
  if (event.key === "[") step(-1);
  else if (event.key === "]") step(1);
}
onMounted(() => window.addEventListener("keydown", onKey));
onBeforeUnmount(() => window.removeEventListener("keydown", onKey));
</script>

<template>
  <ApSelect
    v-if="options.length > 0"
    v-model="model"
    label="Spacecraft"
    hidden-label
    size="compact"
    mono
    :options="choices"
  />
</template>
