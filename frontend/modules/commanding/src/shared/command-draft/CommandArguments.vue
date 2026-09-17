<script setup lang="ts">
import { reactive, watch } from "vue";
import CadenceChoiceField from "@cadence/ui/CadenceChoiceField.vue";
import {
  argumentValuesJson,
  exactInteger,
  parseArgumentValues,
  scalarInputText,
} from "./exact-values";
import type { Argument } from "./contracts";
import type { ArgumentEditorDraft } from "./argument-editor";
const props = withDefaults(
  defineProps<{
    arguments: Argument[];
    supplied?: string;
    idPrefix: string;
    heading?: string;
    draft?: ArgumentEditorDraft;
    compact?: boolean;
  }>(),
  { heading: "Arguments" },
);
const emit = defineEmits<{ edited: []; "update:draft": [draft: ArgumentEditorDraft] }>();
const values = reactive<ArgumentEditorDraft["values"]>(Object.create(null));
function initialize(supplied?: string) {
  const suppliedValues = supplied === undefined ? undefined : parseArgumentValues(supplied);
  for (const a of props.arguments) {
    const value = suppliedValues?.[a.name] ?? a.default_value_json;
    values[a.name] =
      value == null
        ? a.type === "boolean"
          ? ""
          : undefined
        : a.type === "enumerated"
          ? value
          : scalarInputText(value);
  }
}
function restore() {
  initialize(props.supplied);
  if (props.draft) {
    Object.assign(values, props.draft.values);
  }
}
function snapshot(): ArgumentEditorDraft {
  return { values: { ...values } };
}
function edited() {
  emit("update:draft", snapshot());
  emit("edited");
}
watch(() => props.arguments, restore, { immediate: true });
function enumSelection(a: Argument, value = values[a.name]): string | null {
  if (!value) return null;
  try {
    const raw = scalarInputText(value);
    if (!/^[+-]?\d+$/.test(raw)) return null;
    return (
      a.choices.find((choice) => choice.value_json === BigInt(raw).toString())?.value_json ?? null
    );
  } catch {
    return null;
  }
}
function choose(a: Argument, value: string) {
  values[a.name] = value;
  edited();
}
function enumLabel(a: Argument, value: string) {
  return a.choices.find((choice) => choice.value_json === enumSelection(a, value))?.label ?? value;
}
function argumentValue(a: Argument): string {
  const raw = values[a.name];
  if (raw === undefined)
    throw Error(`${a.type === "enumerated" ? "Choose" : "Enter"} a value for ${a.name}.`);
  if (a.type === "enumerated") {
    if (enumSelection(a) === null) throw Error(`Choose a value for ${a.name}.`);
    return raw;
  }
  if (a.type === "boolean") {
    if (!["true", "false"].includes(raw)) throw Error(`Choose a value for ${a.name}.`);
    return raw;
  }
  if (a.type === "integer") {
    try {
      return exactInteger(raw);
    } catch {
      throw Error(`Enter a valid integer for ${a.name}.`);
    }
  }
  if (a.type === "float") {
    if (!/^-?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$/.test(raw) || !Number.isFinite(Number(raw)))
      throw Error(`Enter a valid number for ${a.name}.`);
    return JSON.stringify(Number(raw));
  }
  return JSON.stringify(raw);
}
function collect(): string {
  return argumentValuesJson(
    Object.fromEntries(
      props.arguments
        .filter((a) => a.fixed_value_json === null)
        .map((a) => [a.name, argumentValue(a)]),
    ),
  );
}
const format = (value: unknown) =>
  value === null
    ? "Not recorded"
    : typeof value === "object"
      ? JSON.stringify(value, null, 2)
      : String(value);
defineExpose({ initialize, collect, snapshot });
</script>
<template>
  <section
    :class="
      compact ? 'command-arguments--compact' : 'border border-base-300 bg-base-100 p-4 space-y-5'
    "
    :aria-labelledby="`${idPrefix}-arguments-title`"
  >
    <h2 :id="`${idPrefix}-arguments-title`" class="ca-heading font-semibold text-sm">
      {{ heading }}
    </h2>
    <p v-if="!arguments.length" class="text-sm text-base-content/60">
      This command has no arguments.
    </p>
    <div
      v-for="(arg, index) in arguments"
      :key="arg.id"
      class="ca-argument border-t border-base-300"
    >
      <div class="flex flex-wrap items-center justify-between gap-2">
        <label
          v-if="arg.fixed_value_json === null && arg.type !== 'enumerated'"
          :for="`${idPrefix}-argument-${index}`"
          class="ca-label font-medium text-sm"
          >{{ arg.name }}
          <span class="text-xs text-[var(--text-subtle)]">{{ arg.type }}</span></label
        ><span v-else class="ca-label font-medium text-sm"
          >{{ arg.name }}
          <span v-if="arg.type !== 'enumerated'" class="text-xs text-[var(--text-subtle)]">{{
            arg.type
          }}</span></span
        >
      </div>
      <p v-if="arg.description" class="text-xs text-base-content/60">
        {{ arg.description }}
      </p>
      <p v-if="arg.fixed_value_json !== null" class="font-mono text-sm">
        Fixed:
        {{
          arg.type === "enumerated"
            ? enumLabel(arg, arg.fixed_value_json)
            : format(arg.fixed_value_json)
        }}
      </p>
      <template v-else-if="arg.type === 'enumerated'">
        <CadenceChoiceField
          v-if="arg.choices.length"
          :id="`${idPrefix}-argument-${index}`"
          :label="arg.name"
          hide-label
          :data-argument-name="arg.name"
          :options="
            arg.choices.map((choice) => ({ label: choice.label, value: choice.value_json }))
          "
          :model-value="enumSelection(arg)"
          required
          @update:model-value="choose(arg, $event)"
        />
        <p v-else class="text-xs text-base-content/60">Catalog choices are unavailable.</p>
      </template>
      <template v-else>
        <select
          v-if="arg.type === 'boolean'"
          :id="`${idPrefix}-argument-${index}`"
          v-model="values[arg.name]"
          class="select select-bordered w-full"
          required
          :data-argument-name="arg.name"
          @change="edited"
        >
          <option value="" disabled>Choose true or false</option>
          <option value="true">True</option>
          <option value="false">False</option>
        </select>
        <div v-else class="flex gap-2">
          <input
            :id="`${idPrefix}-argument-${index}`"
            v-model="values[arg.name]"
            type="text"
            aria-required="true"
            :inputmode="arg.type === 'integer' || arg.type === 'float' ? 'decimal' : 'text'"
            class="input input-bordered min-w-0 w-full font-mono"
            :data-argument-name="arg.name"
            @input="edited"
          />
        </div>
      </template>
      <p v-if="JSON.parse(arg.hazardous_values_json).length" class="text-xs text-warning">
        Hazardous values: {{ arg.hazardous_values_json }}
      </p>
    </div>
  </section>
</template>

<style scoped>
.ca-argument {
  display: grid;
  gap: 8px;
  padding-top: 16px;
}
.command-arguments--compact {
  display: grid;
  gap: calc(3 * var(--workspace-space, 4px));
}
.command-arguments--compact .ca-argument {
  gap: calc(1.5 * var(--workspace-space, 4px));
  padding-top: calc(2 * var(--workspace-space, 4px));
}
.command-arguments--compact .ca-heading {
  font-size: var(--workspace-heading-size, 14px);
  line-height: 1.4;
}
.command-arguments--compact .ca-label {
  font-size: var(--workspace-label-size, 14px);
  line-height: 1.4;
}
</style>
