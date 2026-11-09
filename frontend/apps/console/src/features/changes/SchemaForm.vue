<script setup lang="ts">
import { ApField, ApSelect } from "@/ui";
import { visible, type FormValues, type KindSchema } from "./kindSchema.ts";

/** A change-set edit form generated from a kind schema (never hand-written per field). */
defineProps<{ schema: KindSchema; errors: Readonly<Record<string, string>> }>();
const values = defineModel<FormValues>({ required: true });
const option = (v: unknown) => (typeof v === "string" ? v : JSON.stringify(v));
function set(path: string, value: string) {
  values.value = { ...values.value, [path]: value };
}
</script>

<template>
  <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
    <template v-for="f in schema.fields" :key="f.path">
      <template v-if="visible(f, values)">
        <ApSelect
          v-if="f.type === 'enum' || f.type === 'boolean'"
          :label="f.label"
          :model-value="values[f.path] ?? ''"
          :options="
            f.type === 'boolean'
              ? [
                  { value: 'true', label: 'Yes' },
                  { value: 'false', label: 'No' },
                ]
              : (f.enum ?? []).map((o) => ({ value: option(o.value), label: o.label }))
          "
          placeholder="Choose…"
          :hint="f.help ?? undefined"
          :error="errors[f.path] ?? null"
          @update:model-value="set(f.path, $event)"
        />
        <ApField
          v-else
          :label="f.label"
          :model-value="values[f.path] ?? ''"
          :mono="f.type === 'integer'"
          :unit="f.unit ?? undefined"
          :inputmode="f.type === 'integer' ? 'numeric' : undefined"
          :hint="f.help ?? undefined"
          :error="errors[f.path] ?? null"
          :required="f.required"
          @update:model-value="set(f.path, $event)"
        />
      </template>
    </template>
  </div>
</template>
