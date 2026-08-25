<script setup lang="ts">
import {DropdownMenuItem} from "reka-ui"
import {CadencePrimitiveChild} from "./cadence_primitive_child.js"

defineOptions({inheritAttrs: false})

const props = withDefaults(
  defineProps<{
    active: boolean
    disabled?: boolean
  }>(),
  {disabled: false},
)

const emit = defineEmits<{
  select: [event: Event]
}>()
</script>

<template>
  <DropdownMenuItem
    v-if="props.active"
    :disabled="props.disabled"
    as-child
    @select="emit('select', $event)"
  >
    <CadencePrimitiveChild
      :enforce-attrs="['role', 'tabindex', 'aria-disabled', 'data-disabled']"
    >
      <slot></slot>
    </CadencePrimitiveChild>
  </DropdownMenuItem>
  <slot v-else></slot>
</template>
