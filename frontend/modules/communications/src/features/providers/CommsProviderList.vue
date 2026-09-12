<script setup lang="ts">
import { pageContentAttrs } from "@cadence/ui/page-chrome";
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
import { presentationBreadcrumbs } from "@cadence/ui/page-chrome";
import CommsProviderTable from "./CommsProviderTable.vue";

import type { Presentation } from "./provider-list.contracts";

const props = defineProps<{ presentation: Presentation }>();
</script>

<template>
  <div v-bind="pageContentAttrs(props.presentation.root.attrs)">
    <CadencePageHeading
      :breadcrumbs="presentationBreadcrumbs(props.presentation.header.breadcrumbs)"
    >
      <template #title>{{ props.presentation.header.title.text }} </template>
      <template #description>{{ props.presentation.header.subtitle.text }}</template>
      <template #metadata
        ><span>
          {{ props.presentation.header.title.suffix.text }}
        </span></template
      >
      <template #actions
        ><a v-bind="props.presentation.header.actions.new_provider.attrs">
          <span v-bind="props.presentation.header.actions.new_provider.icon.attrs"></span>
          {{ props.presentation.header.actions.new_provider.text }}
        </a></template
      >
    </CadencePageHeading>

    <div v-if="props.presentation.empty_state" v-bind="props.presentation.empty_state.attrs">
      <p v-bind="props.presentation.empty_state.title.attrs">
        {{ props.presentation.empty_state.title.text }}
      </p>
      <p v-bind="props.presentation.empty_state.description.attrs">
        {{ props.presentation.empty_state.description.text }}
      </p>
      <div v-bind="props.presentation.empty_state.action_container.attrs">
        <a v-bind="props.presentation.empty_state.action.attrs">
          <span v-bind="props.presentation.empty_state.action.icon.attrs"></span>
          {{ props.presentation.empty_state.action.text }}
        </a>
      </div>
    </div>

    <section v-else-if="props.presentation.card" v-bind="props.presentation.card.attrs">
      <div v-bind="props.presentation.card.body.attrs">
        <div v-bind="props.presentation.card.table_component.attrs">
          <CommsProviderTable :rows="props.presentation.card.rows" />
        </div>
      </div>
    </section>
  </div>
</template>
