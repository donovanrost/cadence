<script setup lang="ts">
import { pageContentAttrs } from "@cadence/ui/page-chrome";
import { useManagementHeader } from "@cadence/plugin-sdk/page-header";
import SpacecraftList from "./SpacecraftList.vue";

import type { DirectoryData, NavigateDirectory } from "./contracts";
const props = defineProps<DirectoryData & { navigate?: NavigateDirectory; navigating?: boolean }>();
useManagementHeader("/missions/:mission_id/spacecraft", () => ({
  description: props.presentation.header.subtitle.text,
}));
</script>
<template>
  <div v-bind="pageContentAttrs(props.presentation.root.attrs)">
    <SpacecraftList
      :summary_tiles="props.presentation.summary_tiles"
      :roster="props.presentation.roster"
      :profiles="props.presentation.profiles"
      v-bind="props.navigate ? { navigate: props.navigate } : {}"
      :navigating="props.navigating"
    />
  </div>
</template>
