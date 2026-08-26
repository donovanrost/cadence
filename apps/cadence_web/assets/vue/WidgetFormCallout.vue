<script setup lang="ts">
import type {CalloutPresentation} from "./widget_form_callout"

defineProps<{callout: CalloutPresentation}>()
</script>

<template>
  <p :class="callout.class" v-bind="callout.attrs">
    <span :class="[callout.icon.name, callout.icon.class]"></span>
    <span>{{ callout.text }}</span>
  </p>
</template>
