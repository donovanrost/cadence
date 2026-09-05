<script setup lang="ts">
import CadenceBreadcrumbs from "./CadenceBreadcrumbs.vue";
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
  <header v-bind="props.header.attrs">
    <div v-bind="props.header.body.attrs">
      <div v-bind="props.header.content.attrs">
        <CadenceBreadcrumbs :breadcrumbs="props.header.breadcrumbs" />
        <h1 v-bind="props.header.title.attrs">
          {{ props.header.title.text }}
          <span v-if="props.header.title.suffix" v-bind="props.header.title.suffix.attrs">
            {{ props.header.title.suffix.text }}
          </span>
        </h1>
        <p v-if="props.header.subtitle" v-bind="props.header.subtitle.attrs">
          {{ props.header.subtitle.text }}
        </p>
      </div>
      <div v-bind="props.header.actions.attrs">
        <a v-bind="props.action.attrs">
          <span v-if="props.action.icon" v-bind="props.action.icon.attrs"></span>
          {{ props.action.text }}
        </a>
      </div>
    </div>
  </header>
</template>
