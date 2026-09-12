<script setup lang="ts">
import { pageContentAttrs } from "@cadence/ui/page-chrome";
import SpacecraftTypeList from "./SpacecraftTypeList.vue";
import CadenceEmptyStateFrame from "@cadence/ui/CadenceEmptyStateFrame.vue";
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
import type { ProfileDirectory } from "./contracts";
const props = defineProps<{ presentation: ProfileDirectory }>();
</script>
<template>
  <div v-bind="pageContentAttrs(props.presentation.root.attrs)">
    <CadencePageHeading>
      <template #title>{{ props.presentation.header.title.text }}</template>
      <template #description>{{ props.presentation.header.subtitle.text }}</template>
      <template #actions>
        <a
          :id="props.presentation.header.actions.new_profile.id"
          :href="props.presentation.header.actions.new_profile.href"
          data-phx-link="redirect"
          data-phx-link-state="push"
          class="btn btn-primary btn-sm"
        >
          {{ props.presentation.header.actions.new_profile.label }}
        </a>
      </template>
    </CadencePageHeading>

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
