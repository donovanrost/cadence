<script setup lang="ts">
import {CollapsibleRoot} from "reka-ui"
import {provide, toRef} from "vue"

defineOptions({inheritAttrs: false})

const props = withDefaults(
  defineProps<{
    open: boolean
    contentId: string
    disabled?: boolean
  }>(),
  {disabled: false},
)

const emit = defineEmits<{
  "request-change": [open: boolean]
}>()

provide("cadence-collapsible", {contentId: toRef(props, "contentId")})
</script>

<template>
  <CollapsibleRoot
    :open="props.open"
    :disabled="props.disabled"
    :unmount-on-hide="true"
    as-child
    @update:open="emit('request-change', $event)"
  >
    <slot :open="props.open" :disabled="props.disabled"></slot>
  </CollapsibleRoot>
</template>
