<script setup lang="ts">
import { Toggle } from "reka-ui";
import { CadencePrimitiveChild } from "./cadence_primitive_child";

defineOptions({ inheritAttrs: false });

const props = withDefaults(
  defineProps<{
    pressed: boolean;
    disabled?: boolean;
  }>(),
  { disabled: false },
);

const emit = defineEmits<{
  "request-change": [pressed: boolean];
}>();
</script>

<template>
  <Toggle
    :model-value="props.pressed"
    :disabled="props.disabled"
    as-child
    @update:model-value="emit('request-change', $event)"
  >
    <CadencePrimitiveChild
      contract-name="CadenceToggle"
      required-tag="button"
      :enforce-attrs="['aria-pressed', 'data-state', 'data-disabled', 'disabled']"
    >
      <slot :pressed="props.pressed" :disabled="props.disabled"></slot>
    </CadencePrimitiveChild>
  </Toggle>
</template>
