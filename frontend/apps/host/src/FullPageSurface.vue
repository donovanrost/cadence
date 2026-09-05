<script setup lang="ts">
import type { FullPageSurfaceProps } from "@cadence/plugin-sdk";
import type { Component } from "vue";

const props = defineProps<{
  renderer: Component;
  mount: FullPageSurfaceProps;
}>();
</script>

<template>
  <component :is="props.renderer" :bridge="props.mount.bridge" :context="props.mount.context" />
</template>
