<script setup lang="ts">
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

defineProps<{ presentation: MissionListPresentation }>();
</script>

<template>
  <div :class="presentation.root_class">
    <header :class="presentation.header.class">
      <div :class="presentation.header.content_class">
        <div>
          <p :class="presentation.header.eyebrow.class">
            {{ presentation.header.eyebrow.text }}
          </p>
          <h1 :class="presentation.header.title.class">
            {{ presentation.header.title.text }}
            <span :class="presentation.header.title.suffix.class">
              {{ presentation.header.title.suffix.text }}
            </span>
          </h1>
        </div>
        <div :class="presentation.header.actions_class">
          <a v-bind="presentation.header.action.attrs" :class="presentation.header.action.class">
            <span :class="presentation.header.action.icon_class"></span>
            {{ presentation.header.action.label }}
          </a>
        </div>
      </div>
    </header>

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
