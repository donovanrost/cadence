<script setup lang="ts" generic="Value extends string">
/** Radio card. Group several under a <fieldset> with a <legend class="ap-label">. */
defineProps<{
  value: Value;
  name: string;
  title: string;
  description?: string | undefined;
  disabled?: boolean | undefined;
}>();
const model = defineModel<Value | null>({ required: true });
</script>

<template>
  <label
    class="flex cursor-pointer items-start gap-3 border p-3"
    :class="
      model === value
        ? 'border-readout bg-[var(--apogee-wash-action)]'
        : 'border-line hover:bg-raised'
    "
  >
    <input
      v-model="model"
      type="radio"
      :name="name"
      :value="value"
      :disabled="disabled"
      class="mt-1 accent-[var(--color-readout)] [color-scheme:dark]"
    />
    <span class="flex flex-col gap-1">
      <span class="text-base font-semibold text-readout">{{ title }}</span>
      <span v-if="description" class="text-md text-text-3">{{ description }}</span>
    </span>
  </label>
</template>
