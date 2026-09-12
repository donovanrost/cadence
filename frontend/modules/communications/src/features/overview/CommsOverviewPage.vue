<script setup lang="ts">
import { pageContentAttrs } from "@cadence/ui/page-chrome";
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
import CommsOverview from "./CommsOverview.vue";
import type { CommsOverviewPresentation } from "./contracts";

const props = defineProps<{ presentation: CommsOverviewPresentation }>();
</script>

<template>
  <div v-bind="pageContentAttrs(props.presentation.root.attrs)">
    <CadencePageHeading>
      <template #title>{{ props.presentation.header.title.text }} </template>
      <template #eyebrow>{{ props.presentation.header.eyebrow.text }}</template>
      <template #metadata
        ><span>
          {{ props.presentation.header.title_suffix.text }}
        </span></template
      >
    </CadencePageHeading>

    <CommsOverview :overview="props.presentation.overview" />
  </div>
</template>
