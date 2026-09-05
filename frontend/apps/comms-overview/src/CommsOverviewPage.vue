<script setup lang="ts">
import CommsOverview from "./CommsOverview.vue";
import type { CommsOverviewPresentation } from "./comms-overview";

const props = defineProps<{ presentation: CommsOverviewPresentation }>();
</script>

<template>
  <div v-bind="props.presentation.root.attrs">
    <header v-bind="props.presentation.header.attrs">
      <div v-bind="props.presentation.header.body.attrs">
        <div v-bind="props.presentation.header.content.attrs">
          <p v-bind="props.presentation.header.eyebrow.attrs">
            {{ props.presentation.header.eyebrow.text }}
          </p>
          <h1 v-bind="props.presentation.header.title.attrs">
            {{ props.presentation.header.title.text }}
            <span v-bind="props.presentation.header.title_suffix.attrs">
              {{ props.presentation.header.title_suffix.text }}
            </span>
          </h1>
        </div>
      </div>
    </header>

    <CommsOverview :overview="props.presentation.overview" />
  </div>
</template>
