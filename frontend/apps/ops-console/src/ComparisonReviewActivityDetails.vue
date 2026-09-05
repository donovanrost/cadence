<script setup lang="ts">
import { computed } from "vue";

type Attributes = Record<string, string | null>;

type IconPresentation = {
  name: string;
  class: string;
};

type LinkPresentation = {
  key: string;
  href: string;
  class: string;
  text: string;
  attrs: Attributes;
};

type DetailRowPresentation = {
  key: string;
  kind: "text" | "placement_links";
  label: string;
  label_class: string;
  value: string;
  value_class: string;
  value_attrs: Attributes;
  links_class: string;
  links: LinkPresentation[];
  empty_text: string;
};

type BadgePresentation = {
  class: string;
  text: string;
  attrs: Attributes;
  icon?: IconPresentation;
};

type ActionButtonPresentation = {
  id: string;
  type: "button" | "submit";
  class: string;
  text: string;
  icon: IconPresentation;
  attrs: Attributes;
};

type InputPresentation = {
  key: string;
  attrs: Attributes;
};

type TextInputPresentation = {
  wrapper_class: string;
  attrs: Attributes;
};

type FormPresentation = {
  id: string;
  class: string;
  attrs: Attributes;
  hidden_fields: InputPresentation[];
  text_input: TextInputPresentation | null;
  button: ActionButtonPresentation;
};

type FindingPresentation = {
  key: string;
  class: string;
  attrs: Attributes;
  placement_link: Omit<LinkPresentation, "key">;
  status: {
    class: string;
    text: string;
  };
  status_class: string;
  bulk_decision_badge: BadgePresentation;
};

type RootPresentation = {
  class: string;
  attrs: Attributes;
};

type RequestPresentation = {
  kind: "request";
  root: RootPresentation;
  details: {
    class: string;
    rows: DetailRowPresentation[];
  };
  actions: {
    class: string;
    resolved_badge: BadgePresentation | null;
    workflow_button: ActionButtonPresentation | null;
    skipped_badge: BadgePresentation | null;
    unavailable_badge: BadgePresentation | null;
    bulk_form: FormPresentation | null;
    resolve_form: FormPresentation | null;
  };
  findings: null | {
    class: string;
    attrs: Attributes;
    items: FindingPresentation[];
  };
};

type ResolutionPresentation = {
  kind: "resolution";
  root: RootPresentation;
  details: {
    class: string;
    rows: DetailRowPresentation[];
  };
};

type Presentation = RequestPresentation | ResolutionPresentation;

const props = defineProps<{ presentation: Presentation }>();

const request = computed(() => (props.presentation.kind === "request" ? props.presentation : null));

const resolution = computed(() =>
  props.presentation.kind === "resolution" ? props.presentation : null,
);
</script>

<template>
  <div v-if="request" :class="request.root.class" v-bind="request.root.attrs">
    <dl :class="request.details.class">
      <template v-for="row in request.details.rows" :key="row.key">
        <dt :class="row.label_class">{{ row.label }}</dt>
        <dd :class="row.value_class" v-bind="row.value_attrs">
          <template v-if="row.kind === 'placement_links'">
            <div :class="row.links_class">
              <a
                v-for="link in row.links"
                :key="link.key"
                :href="link.href"
                :class="link.class"
                v-bind="link.attrs"
              >
                {{ link.text }}
              </a>
              <span v-if="row.links.length === 0">{{ row.empty_text }}</span>
            </div>
          </template>
          <template v-else>{{ row.value }}</template>
        </dd>
      </template>
    </dl>

    <div :class="request.actions.class">
      <span
        v-if="request.actions.resolved_badge"
        :class="request.actions.resolved_badge.class"
        v-bind="request.actions.resolved_badge.attrs"
      >
        {{ request.actions.resolved_badge.text }}
      </span>

      <button
        v-if="request.actions.workflow_button"
        :id="request.actions.workflow_button.id"
        :type="request.actions.workflow_button.type"
        :class="request.actions.workflow_button.class"
        v-bind="request.actions.workflow_button.attrs"
      >
        <span
          :class="[
            request.actions.workflow_button.icon.name,
            request.actions.workflow_button.icon.class,
          ]"
        ></span>
        {{ request.actions.workflow_button.text }}
      </button>

      <span
        v-if="request.actions.skipped_badge"
        :class="request.actions.skipped_badge.class"
        v-bind="request.actions.skipped_badge.attrs"
      >
        <span
          v-if="request.actions.skipped_badge.icon"
          :class="[
            request.actions.skipped_badge.icon.name,
            request.actions.skipped_badge.icon.class,
          ]"
        ></span>
        {{ request.actions.skipped_badge.text }}
      </span>

      <span
        v-if="request.actions.unavailable_badge"
        :class="request.actions.unavailable_badge.class"
        v-bind="request.actions.unavailable_badge.attrs"
      >
        <span
          v-if="request.actions.unavailable_badge.icon"
          :class="[
            request.actions.unavailable_badge.icon.name,
            request.actions.unavailable_badge.icon.class,
          ]"
        ></span>
        {{ request.actions.unavailable_badge.text }}
      </span>

      <form
        v-if="request.actions.bulk_form"
        :id="request.actions.bulk_form.id"
        :class="request.actions.bulk_form.class"
        v-bind="request.actions.bulk_form.attrs"
      >
        <input
          v-for="field in request.actions.bulk_form.hidden_fields"
          :key="field.key"
          v-bind="field.attrs"
        />
        <button
          :id="request.actions.bulk_form.button.id"
          :type="request.actions.bulk_form.button.type"
          :class="request.actions.bulk_form.button.class"
          v-bind="request.actions.bulk_form.button.attrs"
        >
          <span
            :class="[
              request.actions.bulk_form.button.icon.name,
              request.actions.bulk_form.button.icon.class,
            ]"
          ></span>
          {{ request.actions.bulk_form.button.text }}
        </button>
      </form>

      <form
        v-if="request.actions.resolve_form"
        :id="request.actions.resolve_form.id"
        :class="request.actions.resolve_form.class"
        v-bind="request.actions.resolve_form.attrs"
      >
        <input
          v-for="field in request.actions.resolve_form.hidden_fields"
          :key="field.key"
          v-bind="field.attrs"
        />
        <div
          v-if="request.actions.resolve_form.text_input"
          :class="request.actions.resolve_form.text_input.wrapper_class"
        >
          <label>
            <input v-bind="request.actions.resolve_form.text_input.attrs" />
          </label>
        </div>
        <button
          :id="request.actions.resolve_form.button.id"
          :type="request.actions.resolve_form.button.type"
          :class="request.actions.resolve_form.button.class"
          v-bind="request.actions.resolve_form.button.attrs"
        >
          <span
            :class="[
              request.actions.resolve_form.button.icon.name,
              request.actions.resolve_form.button.icon.class,
            ]"
          ></span>
          {{ request.actions.resolve_form.button.text }}
        </button>
      </form>
    </div>

    <ul v-if="request.findings" :class="request.findings.class" v-bind="request.findings.attrs">
      <li
        v-for="finding in request.findings.items"
        :key="finding.key"
        :class="finding.class"
        v-bind="finding.attrs"
      >
        <a
          :href="finding.placement_link.href"
          :class="finding.placement_link.class"
          v-bind="finding.placement_link.attrs"
        >
          {{ finding.placement_link.text }}
        </a>
        <div :class="finding.status_class">
          <span :class="finding.status.class">{{ finding.status.text }}</span>
          <span
            :class="finding.bulk_decision_badge.class"
            v-bind="finding.bulk_decision_badge.attrs"
          >
            {{ finding.bulk_decision_badge.text }}
          </span>
        </div>
      </li>
    </ul>
  </div>

  <div v-if="resolution" :class="resolution.root.class" v-bind="resolution.root.attrs">
    <dl :class="resolution.details.class">
      <template v-for="row in resolution.details.rows" :key="row.key">
        <dt :class="row.label_class">{{ row.label }}</dt>
        <dd :class="row.value_class" v-bind="row.value_attrs">{{ row.value }}</dd>
      </template>
    </dl>
  </div>
</template>
