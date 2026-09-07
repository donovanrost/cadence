<script setup lang="ts">
import CadencePresentationNode from "@cadence/ui/CadencePresentationNode.vue";
import type { PresentationNode } from "@cadence/ui/presentation_types";

const props = defineProps<{ presentation: PresentationNode }>();
</script>

<template>
  <CadencePresentationNode :node="props.presentation" />
</template>
