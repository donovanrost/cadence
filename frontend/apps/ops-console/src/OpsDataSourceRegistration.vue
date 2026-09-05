<script setup>
import OpsDataSources from "./OpsDataSources.vue";

defineOptions({ inheritAttrs: false });
</script>

<template>
  <OpsDataSources v-bind="$attrs" />
</template>
