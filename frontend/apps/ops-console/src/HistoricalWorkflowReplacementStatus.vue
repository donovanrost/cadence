<script setup lang="ts">
type Attributes = Record<string, string>;

type TextPresentation = {
  class: string;
  text: string;
};

type IconPresentation = {
  name: string;
  class: string;
};

type ButtonPresentation = {
  id: string;
  type: "button" | "submit";
  class: string;
  attrs: Attributes;
};

type ActionButtonPresentation = ButtonPresentation & {
  text: string;
  icon: IconPresentation;
};

type RemainingWorkEntryPresentation = {
  key: string;
  class: string;
  attrs: Attributes;
  header: {
    class: string;
    replacement_run: TextPresentation;
    status: TextPresentation;
  };
  work_details: {
    class: string;
    values: TextPresentation[];
  };
  job_details:
    | {
        visible: true;
        class: string;
        values: TextPresentation[];
      }
    | HiddenPresentation;
  actions: ActionButtonPresentation[];
};

type HiddenPresentation = {
  visible: false;
};

type JobSummaryPresentation =
  | {
      visible: true;
      key: string;
      id: string;
      class: string;
      attrs: Attributes;
      header: {
        class: string;
        label: TextPresentation;
        count: TextPresentation;
      };
      summary: TextPresentation;
    }
  | (HiddenPresentation & { key: string });

type CompletionFormPresentation =
  | {
      visible: true;
      id: string | null;
      class: string;
      attrs: Attributes;
      hidden_fields: Array<{
        key: string;
        attrs: Attributes;
      }>;
      button: ButtonPresentation & {
        label: {
          class: string;
          text: string;
          icon: IconPresentation;
        };
        count: TextPresentation;
      };
    }
  | HiddenPresentation;

type RemainingWorkPresentation =
  | {
      visible: true;
      id: string;
      class: string;
      attrs: Attributes;
      header: {
        class: string;
        label: TextPresentation;
        count: TextPresentation;
      };
      items: {
        class: string;
        entries: RemainingWorkEntryPresentation[];
      };
      job_summaries: JobSummaryPresentation[];
      retry_button:
        | (ButtonPresentation & {
            visible: true;
            label: {
              class: string;
              text: string;
              icon: IconPresentation;
            };
            count: TextPresentation;
          })
        | HiddenPresentation;
    }
  | HiddenPresentation;

type Presentation = {
  remaining_work: RemainingWorkPresentation;
  closure_readiness: {
    id: string;
    class: string;
    attrs: Attributes;
    header: {
      class: string;
      label: TextPresentation;
      status: TextPresentation;
    };
    details: {
      class: string;
      rows: Array<{
        key: string;
        label: TextPresentation;
        value: TextPresentation;
      }>;
    };
    completion_form: CompletionFormPresentation;
  };
};

defineProps<{ presentation: Presentation }>();
</script>

<template>
  <section
    v-if="presentation.remaining_work.visible"
    :id="presentation.remaining_work.id"
    :class="presentation.remaining_work.class"
    v-bind="presentation.remaining_work.attrs"
  >
    <div :class="presentation.remaining_work.header.class">
      <span :class="presentation.remaining_work.header.label.class">
        {{ presentation.remaining_work.header.label.text }}
      </span>
      <span :class="presentation.remaining_work.header.count.class">
        {{ presentation.remaining_work.header.count.text }}
      </span>
    </div>

    <div :class="presentation.remaining_work.items.class">
      <div
        v-for="entry in presentation.remaining_work.items.entries"
        :key="entry.key"
        :class="entry.class"
        v-bind="entry.attrs"
      >
        <div :class="entry.header.class">
          <span :class="entry.header.replacement_run.class">
            {{ entry.header.replacement_run.text }}
          </span>
          <span :class="entry.header.status.class">{{ entry.header.status.text }}</span>
        </div>

        <div :class="entry.work_details.class">
          <span
            v-for="(value, index) in entry.work_details.values"
            :key="`${entry.key}-work-${index}`"
            :class="value.class"
          >
            {{ value.text }}
          </span>
        </div>

        <div v-if="entry.job_details.visible" :class="entry.job_details.class">
          <span
            v-for="(value, index) in entry.job_details.values"
            :key="`${entry.key}-job-${index}`"
            :class="value.class"
          >
            {{ value.text }}
          </span>
        </div>

        <button
          v-for="action in entry.actions"
          :id="action.id"
          :key="action.id"
          :type="action.type"
          :class="action.class"
          v-bind="action.attrs"
        >
          <span :class="[action.icon.name, action.icon.class]"></span>
          {{ action.text }}
        </button>
      </div>
    </div>

    <template v-for="summary in presentation.remaining_work.job_summaries" :key="summary.key">
      <section
        v-if="summary.visible"
        :id="summary.id"
        :class="summary.class"
        v-bind="summary.attrs"
      >
        <div :class="summary.header.class">
          <span :class="summary.header.label.class">{{ summary.header.label.text }}</span>
          <span :class="summary.header.count.class">{{ summary.header.count.text }}</span>
        </div>
        <p :class="summary.summary.class">{{ summary.summary.text }}</p>
      </section>
    </template>

    <button
      v-if="presentation.remaining_work.retry_button.visible"
      :id="presentation.remaining_work.retry_button.id"
      :type="presentation.remaining_work.retry_button.type"
      :class="presentation.remaining_work.retry_button.class"
      v-bind="presentation.remaining_work.retry_button.attrs"
    >
      <span :class="presentation.remaining_work.retry_button.label.class">
        <span
          :class="[
            presentation.remaining_work.retry_button.label.icon.name,
            presentation.remaining_work.retry_button.label.icon.class,
          ]"
        ></span>
        {{ presentation.remaining_work.retry_button.label.text }}
      </span>
      <span :class="presentation.remaining_work.retry_button.count.class">
        {{ presentation.remaining_work.retry_button.count.text }}
      </span>
    </button>
  </section>

  <section
    :id="presentation.closure_readiness.id"
    :class="presentation.closure_readiness.class"
    v-bind="presentation.closure_readiness.attrs"
  >
    <div :class="presentation.closure_readiness.header.class">
      <span :class="presentation.closure_readiness.header.label.class">
        {{ presentation.closure_readiness.header.label.text }}
      </span>
      <span :class="presentation.closure_readiness.header.status.class">
        {{ presentation.closure_readiness.header.status.text }}
      </span>
    </div>

    <dl :class="presentation.closure_readiness.details.class">
      <template v-for="row in presentation.closure_readiness.details.rows" :key="row.key">
        <dt :class="row.label.class">{{ row.label.text }}</dt>
        <dd :class="row.value.class">{{ row.value.text }}</dd>
      </template>
    </dl>

    <form
      v-if="presentation.closure_readiness.completion_form.visible"
      :id="presentation.closure_readiness.completion_form.id ?? undefined"
      :class="presentation.closure_readiness.completion_form.class"
      v-bind="presentation.closure_readiness.completion_form.attrs"
    >
      <input
        v-for="field in presentation.closure_readiness.completion_form.hidden_fields"
        :key="field.key"
        v-bind="field.attrs"
      />
      <button
        :id="presentation.closure_readiness.completion_form.button.id"
        :type="presentation.closure_readiness.completion_form.button.type"
        :class="presentation.closure_readiness.completion_form.button.class"
        v-bind="presentation.closure_readiness.completion_form.button.attrs"
      >
        <span :class="presentation.closure_readiness.completion_form.button.label.class">
          <span
            :class="[
              presentation.closure_readiness.completion_form.button.label.icon.name,
              presentation.closure_readiness.completion_form.button.label.icon.class,
            ]"
          ></span>
          {{ presentation.closure_readiness.completion_form.button.label.text }}
        </span>
        <span :class="presentation.closure_readiness.completion_form.button.count.class">
          {{ presentation.closure_readiness.completion_form.button.count.text }}
        </span>
      </button>
    </form>
  </section>
</template>
