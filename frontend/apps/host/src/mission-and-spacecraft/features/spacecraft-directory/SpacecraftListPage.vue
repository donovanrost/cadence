<script setup lang="ts">
import { pageContentAttrs } from "@cadence/ui/page-chrome";
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
import SpacecraftList from "./SpacecraftList.vue";

import type { DirectoryData, NavigateDirectory } from "./contracts";
const props = defineProps<DirectoryData & { navigate?: NavigateDirectory; navigating?: boolean }>();
</script>
<template>
  <div v-bind="pageContentAttrs(props.presentation.root.attrs)">
    <CadencePageHeading
      :breadcrumbs="
        props.presentation.breadcrumbs.items.map((item) => ({
          label: item.label,
          ...(item.href == null ? {} : { href: item.href }),
        }))
      "
    >
      <template #title>{{ props.presentation.header.title.text }}</template>
      <template #description>{{ props.presentation.header.subtitle.text }}</template>
    </CadencePageHeading>

    <SpacecraftList
      :summary_tiles="props.presentation.summary_tiles"
      :roster="props.presentation.roster"
      :profiles="props.presentation.profiles"
      v-bind="props.navigate ? { navigate: props.navigate } : {}"
      :navigating="props.navigating"
    />
  </div>
</template>
