<script setup lang="ts">
import { useManagementHeader } from "@cadence/plugin-sdk/page-header";
import { serverHref } from "@cadence/plugin-sdk/routes";
import MissionTable from "./MissionTable.vue";

type RawAttrs = Record<string, string>;

type Link = {
  attrs: RawAttrs;
  class: string;
  icon_class: string;
  label: string;
};

type MissionRow = {
  id: string;
  display_name: string;
  slug: string;
  spacecraft_count: number;
  status: "info" | "ready" | "attention";
  status_label: string;
  href: string;
};

type MissionListPresentation = {
  root_class: string;
  header: {
    class: string;
    content_class: string;
    eyebrow: { class: string; text: string };
    title: {
      class: string;
      text: string;
      suffix: { class: string; text: string };
    };
    actions_class: string;
    action: Link;
  };
  empty_state: {
    visible: boolean;
    id: string;
    class: string;
    icon_class: string;
    title: { class: string; text: string };
    description: { class: string; text: string };
    action_container_class: string;
    action: Link;
  };
  card: {
    visible: boolean;
    class: string;
    body_class: string;
    rows: MissionRow[];
  };
};

const props = defineProps<{ presentation: MissionListPresentation }>();
useManagementHeader("/missions", () => ({
  facts: [props.presentation.header.title.suffix.text],
  primary: {
    id: String(props.presentation.header.action.attrs.id ?? "missions-new"),
    label: props.presentation.header.action.label,
    icon: "hero-plus",
    href: serverHref(String(props.presentation.header.action.attrs.href)),
  },
}));
</script>

<template>
  <div :class="presentation.root_class">
    <div v-if="presentation.empty_state.visible" :id="presentation.empty_state.id">
      <div :class="presentation.empty_state.class">
        <span :class="presentation.empty_state.icon_class"></span>
        <p :class="presentation.empty_state.title.class">
          {{ presentation.empty_state.title.text }}
        </p>
        <p :class="presentation.empty_state.description.class">
          {{ presentation.empty_state.description.text }}
        </p>
        <div :class="presentation.empty_state.action_container_class">
          <a
            v-bind="presentation.empty_state.action.attrs"
            :class="presentation.empty_state.action.class"
          >
            <span :class="presentation.empty_state.action.icon_class"></span>
            {{ presentation.empty_state.action.label }}
          </a>
        </div>
      </div>
    </div>

    <section v-else-if="presentation.card.visible" :class="presentation.card.class">
      <div :class="presentation.card.body_class">
        <MissionTable :rows="presentation.card.rows" />
      </div>
    </section>
  </div>
</template>
