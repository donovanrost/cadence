<script setup lang="ts">
import { pageContentAttrs } from "@cadence/ui/page-chrome";
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
import NotificationsPanel from "./NotificationsPanel.vue";

type Attrs = Record<string, string>;

type ElementPresentation = {
  attrs: Attrs;
};

type TextPresentation = ElementPresentation & {
  text: string;
};

type NotificationsPanelProps = InstanceType<typeof NotificationsPanel>["$props"];

type NotificationPayload = {
  notification_id: string;
};

type Presentation = {
  root: ElementPresentation;
  header: {
    attrs: Attrs;
    body: ElementPresentation;
    content: ElementPresentation;
    title: TextPresentation;
    subtitle: TextPresentation;
  };
  empty_state: {
    wrapper: ElementPresentation;
    body: ElementPresentation;
    icon: ElementPresentation;
    title: TextPresentation;
    description: TextPresentation;
  } | null;
  panel: {
    attrs: Attrs;
    notifications: NotificationsPanelProps["notifications"];
  } | null;
};

const props = defineProps<{ presentation: Presentation }>();

const emit = defineEmits<{
  "accept-invitation": [payload: NotificationPayload];
  "mark-read": [payload: NotificationPayload];
}>();
</script>

<template>
  <div v-bind="pageContentAttrs(props.presentation.root.attrs)">
    <CadencePageHeading>
      <template #title>{{ props.presentation.header.title.text }}</template>
      <template #description>{{ props.presentation.header.subtitle.text }}</template>
    </CadencePageHeading>

    <div
      v-if="props.presentation.empty_state"
      v-bind="props.presentation.empty_state.wrapper.attrs"
    >
      <div v-bind="props.presentation.empty_state.body.attrs">
        <span v-bind="props.presentation.empty_state.icon.attrs"></span>
        <p v-bind="props.presentation.empty_state.title.attrs">
          {{ props.presentation.empty_state.title.text }}
        </p>
        <p v-bind="props.presentation.empty_state.description.attrs">
          {{ props.presentation.empty_state.description.text }}
        </p>
      </div>
    </div>

    <div v-else-if="props.presentation.panel" v-bind="props.presentation.panel.attrs">
      <NotificationsPanel
        :notifications="props.presentation.panel.notifications"
        @accept-invitation="emit('accept-invitation', $event)"
        @mark-read="emit('mark-read', $event)"
      />
    </div>
  </div>
</template>
