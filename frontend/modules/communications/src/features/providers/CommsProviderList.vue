<script setup lang="ts">
import { pageContentAttrs } from "@cadence/ui/page-chrome";
import { useManagementHeader } from "@cadence/plugin-sdk/page-header";
import { href } from "@cadence/plugin-sdk/routes";
import CommsProviderTable from "./CommsProviderTable.vue";

import type { Presentation } from "./provider-list.contracts";

const props = defineProps<{ presentation: Presentation; missionId: string }>();
useManagementHeader("/missions/:mission_id/comms/providers", () => ({
  description: props.presentation.header.subtitle.text,
  facts: [props.presentation.header.title.suffix.text],
  primary: {
    id: "new-provider",
    label: props.presentation.header.actions.new_provider.text,
    icon: "hero-plus",
    href: href("/missions/:mission_id/comms/providers/new", { mission_id: props.missionId }),
  },
}));
</script>

<template>
  <div v-bind="pageContentAttrs(props.presentation.root.attrs)">
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
