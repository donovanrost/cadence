<script setup lang="ts">
import SelectedActivityActions from "./SelectedActivityActions.vue";

type DataAttrs = Record<string, string | null>;
type ClassValue = string | Array<string | null>;

type IconPresentation = {
  name: string;
  class: string;
};

type TextPresentation = {
  class: string;
  text: string;
};

type ActionRootPresentation = {
  id?: string;
  class: string;
  attrs?: DataAttrs;
};

type ReadinessReturnPresentation = {
  kind: "readiness_return";
  visible: boolean;
  root: ActionRootPresentation;
  message: TextPresentation;
  action: {
    type: "button";
    class: string;
    text: string;
    icon: IconPresentation;
    attrs: DataAttrs;
  };
};

type SourceActionRow = {
  key: string;
  class: string;
  attrs: DataAttrs;
  message: { text: string };
  occurred_at: TextPresentation;
  source: TextPresentation & { visible: boolean };
};

type SourceActionsPresentation = {
  kind: "source_actions";
  visible: boolean;
  root: ActionRootPresentation;
  latest: TextPresentation;
  rows: SourceActionRow[];
};

type LinkPresentation = {
  id?: string;
  href: string;
  navigation_kind: "navigate" | "patch";
  class: string;
  text: string;
  icon: IconPresentation;
  attrs: DataAttrs;
};

type RecoveryPresentation = {
  kind: "recovery";
  visible: boolean;
  root: ActionRootPresentation;
  message: TextPresentation;
  action: LinkPresentation;
};

type RemediationRow = {
  key: string;
  class: string;
  attrs: DataAttrs;
  label: TextPresentation;
  message: TextPresentation & { visible: boolean };
  action: LinkPresentation | null;
};

type RemediationPresentation = {
  kind: "remediation";
  visible: boolean;
  root: ActionRootPresentation;
  heading: TextPresentation;
  rows: RemediationRow[];
};

type ActionPresentation =
  | ReadinessReturnPresentation
  | SourceActionsPresentation
  | RecoveryPresentation
  | RemediationPresentation;

type ConditionalBadgePresentation = {
  visible: boolean;
  class: ClassValue;
  text: string;
  attrs: DataAttrs;
};

type BadgePresentation = {
  class: ClassValue;
  text: string;
  attrs: DataAttrs;
};

type RefreshPresentation = {
  id: string;
  type: "button";
  class: string;
  text: string;
  icon: IconPresentation;
  attrs: DataAttrs;
};

type FieldPresentation = {
  key: string;
  label: string;
  value: string;
  label_class: string;
  value_class: string;
  attrs: DataAttrs;
};

type Presentation = {
  root: {
    id: string;
    class: ClassValue;
    attrs: DataAttrs;
  };
  header: {
    class: string;
    title: TextPresentation & { attrs: DataAttrs };
    version: ConditionalBadgePresentation;
    filter_state: ConditionalBadgePresentation | null;
    readiness_comparison: BadgePresentation | null;
    refresh: RefreshPresentation | null;
  };
  readiness_return: ReadinessReturnPresentation | null;
  source_actions: SourceActionsPresentation | null;
  recovery: RecoveryPresentation | null;
  fields: FieldPresentation[];
  fields_class: string;
  remediation: RemediationPresentation | null;
};

defineProps<{ presentation: Presentation }>();
</script>

<template>
  <section
    :id="presentation.root.id"
    :class="presentation.root.class"
    v-bind="presentation.root.attrs"
  >
    <div :class="presentation.header.class">
      <span :class="presentation.header.title.class" v-bind="presentation.header.title.attrs">
        {{ presentation.header.title.text }}
      </span>
      <span
        v-if="presentation.header.version.visible"
        :class="presentation.header.version.class"
        v-bind="presentation.header.version.attrs"
      >
        {{ presentation.header.version.text }}
      </span>
      <span
        v-if="presentation.header.filter_state?.visible"
        :class="presentation.header.filter_state.class"
        v-bind="presentation.header.filter_state.attrs"
      >
        {{ presentation.header.filter_state.text }}
      </span>
      <span
        v-if="presentation.header.readiness_comparison"
        :class="presentation.header.readiness_comparison.class"
        v-bind="presentation.header.readiness_comparison.attrs"
      >
        {{ presentation.header.readiness_comparison.text }}
      </span>
      <button
        v-if="presentation.header.refresh"
        :id="presentation.header.refresh.id"
        :type="presentation.header.refresh.type"
        :class="presentation.header.refresh.class"
        v-bind="presentation.header.refresh.attrs"
      >
        <span
          :class="[presentation.header.refresh.icon.name, presentation.header.refresh.icon.class]"
        ></span>
        {{ presentation.header.refresh.text }}
      </button>
    </div>

    <SelectedActivityActions
      v-if="presentation.readiness_return"
      :presentation="presentation.readiness_return"
    />
    <SelectedActivityActions
      v-if="presentation.source_actions"
      :presentation="presentation.source_actions"
    />
    <SelectedActivityActions v-if="presentation.recovery" :presentation="presentation.recovery" />

    <dl v-if="presentation.fields.length > 0" :class="presentation.fields_class">
      <template v-for="field in presentation.fields" :key="field.key">
        <dt :class="field.label_class">{{ field.label }}</dt>
        <dd :class="field.value_class" v-bind="field.attrs">{{ field.value }}</dd>
      </template>
    </dl>

    <SelectedActivityActions
      v-if="presentation.remediation"
      :presentation="presentation.remediation"
    />
  </section>
</template>
