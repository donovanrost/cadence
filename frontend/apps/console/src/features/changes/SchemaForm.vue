<script setup lang="ts">
import { ApSegmented, ApSelect, ApTextarea } from "@/ui";
import SchemaTextField from "./SchemaTextField.vue";
import {
  displayValue,
  visible,
  type FormValues,
  type KindSchema,
  type SchemaField,
} from "./kindSchema.ts";

/** A change-set edit form generated from a kind schema (never hand-written per field; U24 units). */
const props = defineProps<{
  schema: KindSchema;
  errors: Readonly<Record<string, string>>;
  /** Per field path, enum options shown but not choosable (option text; settings #233, ux U96). */
  disabledValues?: Readonly<Record<string, readonly string[]>>;
}>();
const values = defineModel<FormValues>({ required: true });
const option = (v: unknown) => (typeof v === "string" ? v : JSON.stringify(v));
function set(path: string, value: string) {
  values.value = { ...values.value, [path]: value };
}
/** ISO 4217 codes offered for currency fields; the server validates the final value. */
const currencies = ["USD", "EUR", "GBP", "JPY", "CAD", "AUD", "CHF", "NZD", "NOK", "SEK"] as const;
const isCurrency = (f: SchemaField) => f.type === "string" && /(^|\.)currency$/.test(f.path);
/** Enums, currencies, and reference fields the server offers choices for (e.g. catalog revisions). */
const isSelect = (f: SchemaField) =>
  f.type === "enum" || isCurrency(f) || (f.type === "reference" && (f.enum?.length ?? 0) > 0);
const selectOptions = (f: SchemaField) =>
  isCurrency(f)
    ? currencies.map((c) => ({ value: c, label: c }))
    : (f.enum ?? []).map((o) => ({
        value: option(o.value),
        label: o.label,
        disabled: props.disabledValues?.[f.path]?.includes(option(o.value)) ?? false,
      }));
const yesNo = (f: SchemaField) => {
  const def = f.default === true ? "true" : f.default === false ? "false" : null;
  return [
    { value: "true", label: def === "true" ? "Yes · default" : "Yes" },
    { value: "false", label: def === "false" ? "No · default" : "No" },
  ];
};
const defaultText = (f: SchemaField) =>
  f.enum?.find((o) => option(o.value) === option(f.default))?.label ?? displayValue(f, f.default);
const hint = (f: SchemaField) =>
  [
    f.help,
    f.unit === "s" ? "e.g. 48h, 2d, 90m" : null,
    f.default !== null && f.type !== "boolean" ? `Default ${defaultText(f)}` : null,
  ]
    .filter(Boolean)
    .join(" · ") || undefined;
</script>

<template>
  <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
    <template v-for="f in schema.fields" :key="f.path">
      <template v-if="visible(f, values)">
        <div v-if="f.type === 'boolean'" class="flex flex-col gap-1.5">
          <span class="ap-label">{{ f.label }}</span>
          <ApSegmented
            :model-value="values[f.path] || (f.default === true ? 'true' : 'false')"
            :options="yesNo(f)"
            :label="f.label"
            @update:model-value="set(f.path, $event)"
          />
          <span v-if="f.help" class="text-sm text-text-3">{{ f.help }}</span>
        </div>
        <ApSelect
          v-else-if="isSelect(f)"
          :label="f.label"
          :model-value="values[f.path] ?? ''"
          :options="selectOptions(f)"
          placeholder="Choose…"
          :hint="hint(f)"
          :error="errors[f.path] ?? null"
          @update:model-value="set(f.path, $event)"
        />
        <ApTextarea
          v-else-if="f.type === 'text' || f.type === 'json'"
          class="md:col-span-2"
          :label="f.label"
          :model-value="values[f.path] ?? ''"
          :hint="hint(f)"
          :error="errors[f.path] ?? null"
          :required="f.required"
          @update:model-value="set(f.path, $event)"
        />
        <SchemaTextField
          v-else
          :field="f"
          :model-value="values[f.path] ?? ''"
          :hint="hint(f)"
          :error="errors[f.path] ?? null"
          @update:model-value="set(f.path, $event)"
        />
      </template>
    </template>
  </div>
</template>
