<script setup lang="ts">
import CadencePresentationNode from "./ui/components/CadencePresentationNode.vue";
import type { PresentationNode } from "./ui/presentation_types";

const props = defineProps<{ presentation: PresentationNode }>();
</script>

<template>
  <CadencePresentationNode :node="props.presentation" />
</template>
