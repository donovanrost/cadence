<script setup lang="ts">
import { pageContentAttrs } from "@cadence/ui/page-chrome";
import SpacecraftTypeList from "./SpacecraftTypeList.vue";
import CadenceEmptyStateFrame from "@cadence/ui/CadenceEmptyStateFrame.vue";
import { useManagementHeader } from "@cadence/plugin-sdk/page-header";
import { serverHref } from "@cadence/plugin-sdk/routes";
import type { ProfileDirectory } from "./contracts";
const props = defineProps<{ presentation: ProfileDirectory }>();
useManagementHeader("/missions/:mission_id/spacecraft/profiles", () => ({
  description: props.presentation.header.subtitle.text,
  primary: {
    id: props.presentation.header.actions.new_profile.id,
    label: props.presentation.header.actions.new_profile.label,
    icon: "hero-plus",
    href: serverHref(props.presentation.header.actions.new_profile.href),
  },
}));
</script>
<template>
  <div v-bind="pageContentAttrs(props.presentation.root.attrs)">
    <CadenceEmptyStateFrame v-if="props.presentation.empty_state" id="spacecraft-profiles-empty">
      <template #title>{{ props.presentation.empty_state.title }}</template>
      <template #description>{{ props.presentation.empty_state.description }}</template>
    </CadenceEmptyStateFrame>

    <section v-if="props.presentation.card" v-bind="props.presentation.card.attrs">
      <div v-bind="props.presentation.card.body.attrs">
        <div v-bind="props.presentation.card.list_component.attrs">
          <SpacecraftTypeList :rows="props.presentation.card.rows" />
        </div>
      </div>
    </section>
  </div>
</template>
