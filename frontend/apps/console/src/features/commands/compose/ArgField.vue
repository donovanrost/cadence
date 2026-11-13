<script setup lang="ts">
import { computed } from "vue";
import { ApField, ApNumberField, ApSegmented, ApSelect } from "@/ui";
import type { CommandArgument } from "../api.ts";
import { argInput, UNSUPPORTED_ARG } from "../args.ts";

/** One catalog argument (R03: the catalog writes the form). Fixed values are read-only. */
const props = defineProps<{ arg: CommandArgument; error: string | null }>();
const model = defineModel<string>({ required: true });
const input = computed(() => argInput(props.arg));
const label = computed(() => `${props.arg.name}${props.arg.required ? "" : " (optional)"}`);
const options = computed(() =>
  input.value.kind === "choice" ? [{ value: "", label: "Choose…" }, ...input.value.options] : [],
);
const bools = [
  { value: "true", label: "True" },
  { value: "false", label: "False" },
] as const;
</script>

<template>
  <div class="flex flex-col gap-1">
    <p v-if="input.kind === 'fixed'" class="m-0 flex flex-col gap-1">
      <span class="ap-label">{{ arg.name }} · fixed</span>
      <span class="font-mono text-md text-text-2">{{ input.text }}</span>
    </p>
    <ApSelect
      v-else-if="input.kind === 'choice'"
      v-model="model"
      :label="label"
      size="compact"
      :options="options"
      v-bind="error ? { error } : {}"
    />
    <ApSegmented
      v-else-if="input.kind === 'boolean'"
      :model-value="model === 'true' ? 'true' : model === 'false' ? 'false' : ''"
      :options="bools"
      :label="label"
      @update:model-value="(v) => (model = v)"
    />
    <p v-else-if="input.kind === 'unsupported'" class="m-0 flex flex-col gap-1">
      <span class="ap-label">{{ arg.name }}</span>
      <span class="text-sm text-caution-text">{{ UNSUPPORTED_ARG }}</span>
    </p>
    <ApNumberField
      v-else-if="input.kind === 'number'"
      v-model="model"
      :label="label"
      :integer="input.integer"
      v-bind="{
        ...(input.min === undefined ? {} : { min: input.min }),
        ...(input.max === undefined ? {} : { max: input.max }),
        ...(arg.unit ? { unit: arg.unit } : {}),
      }"
    />
    <ApField
      v-else
      v-model="model"
      :label="label"
      mono
      :placeholder="input.hex ? 'hex bytes, e.g. 0A1F' : ''"
      v-bind="error ? { error } : {}"
    />
    <p
      v-if="
        error && input.kind !== 'choice' && input.kind !== 'text' && input.kind !== 'unsupported'
      "
      class="m-0 text-sm text-caution-text"
    >
      {{ error }}
    </p>
    <p v-if="arg.description" class="m-0 text-sm text-text-3">{{ arg.description }}</p>
  </div>
</template>
