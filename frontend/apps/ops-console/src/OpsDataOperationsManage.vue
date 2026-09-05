<script setup>
import OpsDataOperations from "./OpsDataOperations.vue";

defineOptions({ inheritAttrs: false });
</script>

<template>
  <OpsDataOperations v-bind="$attrs" />
</template>
