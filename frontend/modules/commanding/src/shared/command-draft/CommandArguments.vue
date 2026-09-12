<script setup lang="ts">
import { reactive, watch } from "vue";
import { argumentValuesJson, exactInteger, parseArgumentValues } from "./exact-values";
import type { Argument } from "./contracts";
const props = withDefaults(
  defineProps<{
    arguments: Argument[];
    supplied?: string;
    idPrefix: string;
    heading?: string;
  }>(),
  { heading: "Arguments" },
);
const emit = defineEmits<{ edited: [] }>();
const enabled = reactive<Record<string, boolean>>(Object.create(null)),
  values = reactive<Record<string, string>>(Object.create(null)),
  enumType = reactive<Record<string, string>>(Object.create(null));
function initialize(supplied?: string) {
  const suppliedValues = supplied === undefined ? undefined : parseArgumentValues(supplied);
  for (const a of props.arguments) {
    enabled[a.name] = suppliedValues
      ? Object.hasOwn(suppliedValues, a.name)
      : a.required && a.fixed_value_json === null && a.default_value_json === null;
    const value = suppliedValues?.[a.name] ?? a.default_value_json;
    values[a.name] = value == null ? "" : value.startsWith('"') ? JSON.parse(value) : value;
    enumType[a.name] =
      value !== null && value !== undefined && /^-?\d/.test(value) ? "number" : "text";
  }
}
watch(
  () => props.arguments,
  () => initialize(props.supplied),
  { immediate: true },
);
function argumentValue(a: Argument): string {
  const raw = values[a.name] ?? "";
  if (a.type === "boolean") {
    if (!["true", "false"].includes(raw)) throw Error(`Choose a value for ${a.name}.`);
    return raw;
  }
  if (a.type === "integer" || (a.type === "enumerated" && enumType[a.name] === "number")) {
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
        .filter((a) => enabled[a.name] && a.fixed_value_json === null)
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
defineExpose({ initialize, collect });
</script>
<template>
  <section
    class="border border-base-300 bg-base-100 p-4 space-y-5"
    :aria-labelledby="`${idPrefix}-arguments-title`"
  >
    <h2 :id="`${idPrefix}-arguments-title`" class="font-semibold">{{ heading }}</h2>
    <p v-if="!arguments.length" class="text-sm text-base-content/60">
      This command has no arguments.
    </p>
    <div
      v-for="(arg, index) in arguments"
      :key="arg.id"
      class="space-y-2 border-t border-base-300 pt-4"
    >
      <div class="flex flex-wrap items-center justify-between gap-2">
        <label
          v-if="arg.fixed_value_json === null"
          :for="`${idPrefix}-argument-${index}`"
          class="font-medium text-sm"
          >{{ arg.name }} <span class="text-xs text-base-content/50">{{ arg.type }}</span></label
        ><span v-else class="font-medium text-sm"
          >{{ arg.name }} <span class="text-xs text-base-content/50">{{ arg.type }}</span></span
        ><label v-if="arg.fixed_value_json === null" class="flex items-center gap-2 text-xs"
          ><input
            v-model="enabled[arg.name]"
            :disabled="arg.required && arg.default_value_json === null"
            type="checkbox"
            class="checkbox checkbox-xs"
            :data-argument-enabled="arg.name"
            @change="emit('edited')"
          />Supply value</label
        >
      </div>
      <p v-if="arg.description" class="text-xs text-base-content/60">
        {{ arg.description }}
      </p>
      <p v-if="arg.fixed_value_json !== null" class="font-mono text-sm">
        Fixed: {{ format(arg.fixed_value_json) }}
      </p>
      <template v-else-if="enabled[arg.name]">
        <select
          v-if="arg.type === 'boolean'"
          :id="`${idPrefix}-argument-${index}`"
          v-model="values[arg.name]"
          class="select select-bordered w-full"
          :data-argument-name="arg.name"
          @change="emit('edited')"
        >
          <option value="">Choose true or false</option>
          <option value="true">True</option>
          <option value="false">False</option>
        </select>
        <div v-else class="flex gap-2">
          <select
            v-if="arg.type === 'enumerated'"
            v-model="enumType[arg.name]"
            :aria-label="`${arg.name} value type`"
            class="select select-bordered"
            @change="emit('edited')"
          >
            <option value="text">Text</option>
            <option value="number">Number</option></select
          ><input
            :id="`${idPrefix}-argument-${index}`"
            v-model="values[arg.name]"
            type="text"
            :inputmode="arg.type === 'integer' || arg.type === 'float' ? 'decimal' : 'text'"
            class="input input-bordered min-w-0 w-full font-mono"
            :data-argument-name="arg.name"
            @input="emit('edited')"
          />
        </div>
      </template>
      <p v-else class="text-xs text-base-content/60">
        {{
          arg.default_value_json !== null
            ? `Uses default: ${format(arg.default_value_json)}`
            : "Omitted from this request."
        }}
      </p>
      <p v-if="JSON.parse(arg.hazardous_values_json).length" class="text-xs text-warning">
        Hazardous values: {{ arg.hazardous_values_json }}
      </p>
    </div>
  </section>
</template>
