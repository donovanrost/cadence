<script setup lang="ts">
import CadencePageHeading from "./CadencePageHeading.vue";
import { presentationBreadcrumbs } from "./page-chrome";
import type {
  CompactPageHeaderPresentation,
  PageHeaderAction,
  PageHeaderPresentation,
} from "./page_shell";
const props = defineProps<{
  header: PageHeaderPresentation | CompactPageHeaderPresentation;
  action: PageHeaderAction;
}>();
</script>
<template>
  <CadencePageHeading :breadcrumbs="presentationBreadcrumbs(header.breadcrumbs)">
    <template #title>{{ header.title.text }}</template>
    <template v-if="header.title.suffix" #metadata>{{ header.title.suffix.text }}</template>
    <template v-if="header.subtitle" #description>{{ header.subtitle.text }}</template>
    <template #actions>
      <a v-bind="props.action.attrs"
        ><span v-if="props.action.icon" v-bind="props.action.icon.attrs" />{{
          props.action.text
        }}</a
      >
    </template>
  </CadencePageHeading>
</template>
