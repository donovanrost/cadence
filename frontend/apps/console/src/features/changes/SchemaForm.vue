<script setup lang="ts">
import { ApField, ApSegmented, ApSelect, ApTextarea } from "@/ui";
import {
  displayValue,
  visible,
  type FormValues,
  type KindSchema,
  type SchemaField,
} from "./kindSchema.ts";

/** A change-set edit form generated from a kind schema (never hand-written per field; U24 units). */
defineProps<{ schema: KindSchema; errors: Readonly<Record<string, string>> }>();
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
const unitLabel = (f: SchemaField) =>
  f.unit === "s"
    ? "duration"
    : f.unit === "micros"
      ? "amount"
      : f.unit === "ratio"
        ? "%"
        : (f.unit ?? undefined);
const selectOptions = (f: SchemaField) =>
  isCurrency(f)
    ? currencies.map((c) => ({ value: c, label: c }))
    : (f.enum ?? []).map((o) => ({ value: option(o.value), label: o.label }));
/** Numbers, times and lists read in mono (ids and figures). */
const isMono = (f: SchemaField) =>
  ["integer", "number", "datetime", "time", "list"].includes(f.type);
const inputMode = (f: SchemaField) =>
  f.unit === "micros" || f.type === "number"
    ? ("decimal" as const)
    : f.type === "integer" && f.unit !== "s"
      ? ("numeric" as const)
      : undefined;
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
          v-else-if="f.type === 'text'"
          class="md:col-span-2"
          :label="f.label"
          :model-value="values[f.path] ?? ''"
          :hint="hint(f)"
          :error="errors[f.path] ?? null"
          :required="f.required"
          @update:model-value="set(f.path, $event)"
        />
        <ApField
          v-else
          :label="f.label"
          :model-value="values[f.path] ?? ''"
          :mono="isMono(f)"
          :unit="unitLabel(f)"
          :inputmode="inputMode(f)"
          :hint="hint(f)"
          :error="errors[f.path] ?? null"
          :required="f.required"
          @update:model-value="set(f.path, $event)"
        />
      </template>
    </template>
  </div>
</template>
