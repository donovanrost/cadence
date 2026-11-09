<script setup lang="ts">
import { computed, nextTick, onMounted, useTemplateRef } from "vue";
import { ApCallout } from "@/ui";
import ArgField from "./ArgField.vue";
import { checkItem, type StackItem } from "./stack.ts";

/** Inline form for one stack row: every argument from the catalog, errors inline. */
const props = defineProps<{ item: StackItem }>();
const emit = defineEmits<{ change: [values: Record<string, string>]; done: [] }>();
const root = useTemplateRef<HTMLFormElement>("root");
/** Canvas fix #13: the form opens with focus on the first argument; ↵ confirms (closes the row). */
onMounted(() => {
  void nextTick(() =>
    root.value?.querySelector<HTMLElement>("input, select, textarea, [role=radio]")?.focus(),
  );
});
const check = computed(() => checkItem(props.item));
const set = (argId: string, value: string) =>
  emit("change", { ...props.item.values, [argId]: value });
</script>

<template>
  <form
    ref="root"
    class="flex flex-col gap-3 border-t border-hairline-faint bg-vacuum/40 px-4 py-3"
    @submit.prevent="emit('done')"
  >
    <button type="submit" class="sr-only">Done</button>
    <p
      v-if="item.command.arguments.length === 0"
      class="m-0 font-mono text-xs text-text-4 uppercase"
    >
      No arguments
    </p>
    <div class="grid grid-cols-1 gap-3 md:grid-cols-2">
      <ArgField
        v-for="arg in item.command.arguments"
        :key="arg.id"
        :arg="arg"
        :error="check.errors[arg.id] ?? null"
        :model-value="item.values[arg.id] ?? ''"
        @update:model-value="(v) => set(arg.id, v)"
      />
    </div>
    <ApCallout v-if="check.hazardousValues.length" tone="caution">
      The catalog marks the value of {{ check.hazardousValues.join(", ") }} as hazardous.
    </ApCallout>
  </form>
</template>
