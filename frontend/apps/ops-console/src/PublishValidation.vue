<script setup lang="ts">
type DataAttrs = Record<string, string | null>;

type TextPresentation = {
  class: string;
  text: string;
};

type IconPresentation = {
  name: string;
  class: string;
};

type LinkPresentation = {
  href: string;
  navigation_kind: "navigate" | "patch";
  class: string;
  text: string;
  icon?: IconPresentation;
  attrs: DataAttrs;
};

type ValueRow = {
  key: string;
  label: TextPresentation;
  value: TextPresentation & { attrs: DataAttrs };
};

type IssuePresentation = {
  key: string;
  id: string;
  class: string;
  attrs: DataAttrs;
  header: {
    class: string;
    severity: TextPresentation;
    code: TextPresentation;
    focus: LinkPresentation;
  };
  message: TextPresentation & { attrs: DataAttrs };
  summary: null | {
    class: string;
    attrs: DataAttrs;
    rows: ValueRow[];
  };
  action: null | {
    class: string;
    attrs: DataAttrs;
    label: TextPresentation;
    message: TextPresentation;
    link: LinkPresentation | null;
  };
  details: null | {
    class: string;
    rows: ValueRow[];
  };
};

type Presentation = {
  root: {
    id: string;
    class: string;
    attrs: DataAttrs;
  };
  header: {
    class: string;
    heading: TextPresentation;
    controls: { class: string };
    refresh: {
      id: string;
      type: "button";
      class: string;
      text: string;
      icon: IconPresentation;
      attrs: DataAttrs;
    };
    badge: TextPresentation;
  };
  message: TextPresentation;
  result: {
    id: string;
    class: string;
    attrs: DataAttrs;
    label: TextPresentation;
    message: TextPresentation;
  };
  freshness: null | {
    id: string;
    class: string;
    attrs: DataAttrs;
    evaluated: { label: TextPresentation; value: TextPresentation };
    draft_state: { label: TextPresentation; value: TextPresentation };
    reason: {
      visible: boolean;
      label: TextPresentation;
      value: TextPresentation;
    };
    message: TextPresentation & { visible: boolean; attrs: DataAttrs };
  };
  resolved_notice: TextPresentation & { visible: boolean; attrs: DataAttrs };
  issues: {
    visible: boolean;
    class: string;
    rows: IssuePresentation[];
  };
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
      <h3 :class="presentation.header.heading.class">{{ presentation.header.heading.text }}</h3>
      <div :class="presentation.header.controls.class">
        <button
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
        <span :class="presentation.header.badge.class">{{ presentation.header.badge.text }}</span>
      </div>
    </div>
    <p :class="presentation.message.class">{{ presentation.message.text }}</p>
    <div
      :id="presentation.result.id"
      :class="presentation.result.class"
      v-bind="presentation.result.attrs"
    >
      <p :class="presentation.result.label.class">{{ presentation.result.label.text }}</p>
      <p :class="presentation.result.message.class">{{ presentation.result.message.text }}</p>
    </div>
    <div
      v-if="presentation.freshness"
      :id="presentation.freshness.id"
      :class="presentation.freshness.class"
      v-bind="presentation.freshness.attrs"
    >
      <div>
        <p :class="presentation.freshness.evaluated.label.class">
          {{ presentation.freshness.evaluated.label.text }}
        </p>
        <p :class="presentation.freshness.evaluated.value.class">
          {{ presentation.freshness.evaluated.value.text }}
        </p>
      </div>
      <div>
        <p :class="presentation.freshness.draft_state.label.class">
          {{ presentation.freshness.draft_state.label.text }}
        </p>
        <p :class="presentation.freshness.draft_state.value.class">
          {{ presentation.freshness.draft_state.value.text }}
        </p>
      </div>
      <div v-if="presentation.freshness.reason.visible">
        <p :class="presentation.freshness.reason.label.class">
          {{ presentation.freshness.reason.label.text }}
        </p>
        <p :class="presentation.freshness.reason.value.class">
          {{ presentation.freshness.reason.value.text }}
        </p>
      </div>
      <p
        v-if="presentation.freshness.message.visible"
        :class="presentation.freshness.message.class"
        v-bind="presentation.freshness.message.attrs"
      >
        {{ presentation.freshness.message.text }}
      </p>
    </div>
    <p
      v-if="presentation.resolved_notice.visible"
      :class="presentation.resolved_notice.class"
      v-bind="presentation.resolved_notice.attrs"
    >
      {{ presentation.resolved_notice.text }}
    </p>
    <ol v-if="presentation.issues.visible" :class="presentation.issues.class">
      <li
        v-for="issue in presentation.issues.rows"
        :id="issue.id"
        :key="issue.key"
        :class="issue.class"
        v-bind="issue.attrs"
      >
        <div :class="issue.header.class">
          <span :class="issue.header.severity.class">{{ issue.header.severity.text }}</span>
          <span :class="issue.header.code.class">{{ issue.header.code.text }}</span>
          <a
            :href="issue.header.focus.href"
            :class="issue.header.focus.class"
            v-bind="issue.header.focus.attrs"
          >
            {{ issue.header.focus.text }}
          </a>
        </div>
        <p :class="issue.message.class" v-bind="issue.message.attrs">{{ issue.message.text }}</p>
        <dl v-if="issue.summary" :class="issue.summary.class" v-bind="issue.summary.attrs">
          <template v-for="row in issue.summary.rows" :key="row.key">
            <dt :class="row.label.class">{{ row.label.text }}</dt>
            <dd :class="row.value.class" v-bind="row.value.attrs">{{ row.value.text }}</dd>
          </template>
        </dl>
        <div v-if="issue.action" :class="issue.action.class" v-bind="issue.action.attrs">
          <div :class="issue.action.label.class">{{ issue.action.label.text }}</div>
          <p :class="issue.action.message.class">{{ issue.action.message.text }}</p>
          <a
            v-if="issue.action.link"
            :href="issue.action.link.href"
            :class="issue.action.link.class"
            v-bind="issue.action.link.attrs"
          >
            <span
              v-if="issue.action.link.icon"
              :class="[issue.action.link.icon.name, issue.action.link.icon.class]"
            ></span>
            {{ issue.action.link.text }}
          </a>
        </div>
        <dl v-if="issue.details" :class="issue.details.class">
          <template v-for="row in issue.details.rows" :key="row.key">
            <dt :class="row.label.class">{{ row.label.text }}</dt>
            <dd :class="row.value.class" v-bind="row.value.attrs">{{ row.value.text }}</dd>
          </template>
        </dl>
      </li>
    </ol>
  </section>
</template>
