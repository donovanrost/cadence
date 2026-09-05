<script setup lang="ts">
import {useAttrs} from "vue"
import SpacecraftTelemetryDecom from "./SpacecraftTelemetryDecom.vue"

defineOptions({inheritAttrs: false})

const attrs = useAttrs()
</script>

<template>
  <SpacecraftTelemetryDecom v-bind="attrs" />
</template>
