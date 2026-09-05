<script setup lang="ts">
import HistoricalWorkflowReplacementStatus from "./HistoricalWorkflowReplacementStatus.vue";

type Attributes = Record<string, string>;

type TextPresentation = {
  class: string;
  text: string;
};

type IconPresentation = {
  name: string;
  class: string;
};

type DetailRowPresentation = {
  key: string;
  label: TextPresentation;
  value: TextPresentation;
};

type DetailListPresentation = {
  class: string;
  rows: DetailRowPresentation[];
};

type ItemPresentation = {
  key: string;
  class: string;
  text: string;
  attrs: Attributes;
};

type PatchLinkPresentation = {
  key?: string;
  href: string | null;
  class: string;
  text: string;
  icon?: IconPresentation;
  attrs: Attributes;
};

type ActionButtonPresentation = {
  visible: boolean;
  id: string;
  type: "button";
  class: string;
  text: string;
  icon: IconPresentation;
  attrs: Attributes;
};

type SubmitButtonPresentation = {
  id: string;
  type: "submit";
  class: string;
  attrs: Attributes;
  label: TextPresentation & { icon: IconPresentation };
  count: TextPresentation;
};

type AdvancementFormPresentation = {
  visible: boolean;
  id: string | null;
  class: string;
  attrs: Attributes;
  hidden_fields: Array<{
    key: string;
    attrs: Attributes;
  }>;
  header: {
    class: string;
    label: TextPresentation;
    count: TextPresentation;
  };
  preview: TextPresentation;
  button: SubmitButtonPresentation;
};

type ReplacementStatusPresentation = NonNullable<
  InstanceType<typeof HistoricalWorkflowReplacementStatus>["$props"]["presentation"]
>;

type Presentation = {
  root: {
    id: string;
    class: string;
    attrs: Attributes;
  };
  header: {
    class: string;
    label: TextPresentation;
    state: TextPresentation;
  };
  job_progress: {
    visible: boolean;
    id: string;
    class: string;
    attrs: Attributes;
    header: {
      class: string;
      label: TextPresentation;
      progress: TextPresentation;
    };
    items: {
      class: string;
      entries: ItemPresentation[];
    };
  };
  execution_audit: {
    visible: boolean;
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
      entries: Array<{
        key: string;
        class: string;
        attrs: Attributes;
        header: {
          class: string;
          label: TextPresentation;
          count: TextPresentation;
        };
        detail: TextPresentation & { visible: boolean };
      }>;
    };
  };
  review_origin: {
    visible: boolean;
    id: string;
    class: string;
    attrs: Attributes;
    header: {
      class: string;
      label: TextPresentation;
    };
    review_link: PatchLinkPresentation & { icon: IconPresentation };
    placements: {
      visible: boolean;
      class: string;
      attrs: Attributes;
      links: PatchLinkPresentation[];
    };
  };
  details: DetailListPresentation;
  recovery: {
    visible: boolean;
    id: string;
    class: string;
    attrs: Attributes;
    header: {
      class: string;
      label: TextPresentation;
      resolved: TextPresentation;
    };
    review_origin: {
      visible: boolean;
      id: string;
      class: string;
      attrs: Attributes;
      label: TextPresentation;
      review_link: PatchLinkPresentation & { icon: IconPresentation };
    };
    guidance: {
      id: string;
      class: string;
      attrs: Attributes;
      header: {
        class: string;
        label: TextPresentation;
        next_action: TextPresentation;
      };
      guidance: TextPresentation;
      retry_state: TextPresentation & { visible: boolean };
      available_when: TextPresentation & { visible: boolean };
    };
    failed_item_handoffs: {
      visible: boolean;
      id: string;
      class: string;
      attrs: Attributes;
      header: {
        class: string;
        label: TextPresentation;
        count: TextPresentation;
      };
      links: {
        class: string;
        entries: Array<PatchLinkPresentation & { key: string; icon: IconPresentation }>;
      };
    };
    execution_plan: {
      id: string;
      class: string;
      attrs: Attributes;
      header: {
        class: string;
        label: TextPresentation;
        retry_count: TextPresentation;
      };
      details: DetailListPresentation;
      replacement_status: ReplacementStatusPresentation;
      retry_button: ActionButtonPresentation;
      advancement_form: AdvancementFormPresentation;
    };
    details: DetailListPresentation;
    item_groups: Array<{
      key: string;
      visible: boolean;
      class: string;
      attrs: Attributes;
      label: TextPresentation;
      items: ItemPresentation[];
    }>;
    guidance_note: TextPresentation;
  };
};

defineProps<{ presentation: Presentation }>();
</script>

<template>
  <div :id="presentation.root.id" :class="presentation.root.class" v-bind="presentation.root.attrs">
    <div :class="presentation.header.class">
      <span :class="presentation.header.label.class">{{ presentation.header.label.text }}</span>
      <span :class="presentation.header.state.class">{{ presentation.header.state.text }}</span>
    </div>

    <section
      v-if="presentation.job_progress.visible"
      :id="presentation.job_progress.id"
      :class="presentation.job_progress.class"
      v-bind="presentation.job_progress.attrs"
    >
      <div :class="presentation.job_progress.header.class">
        <span :class="presentation.job_progress.header.label.class">
          {{ presentation.job_progress.header.label.text }}
        </span>
        <span :class="presentation.job_progress.header.progress.class">
          {{ presentation.job_progress.header.progress.text }}
        </span>
      </div>
      <div :class="presentation.job_progress.items.class">
        <div
          v-for="item in presentation.job_progress.items.entries"
          :key="item.key"
          :class="item.class"
          v-bind="item.attrs"
        >
          {{ item.text }}
        </div>
      </div>
    </section>

    <section
      v-if="presentation.execution_audit.visible"
      :id="presentation.execution_audit.id"
      :class="presentation.execution_audit.class"
      v-bind="presentation.execution_audit.attrs"
    >
      <div :class="presentation.execution_audit.header.class">
        <span :class="presentation.execution_audit.header.label.class">
          {{ presentation.execution_audit.header.label.text }}
        </span>
        <span :class="presentation.execution_audit.header.count.class">
          {{ presentation.execution_audit.header.count.text }}
        </span>
      </div>
      <div :class="presentation.execution_audit.items.class">
        <div
          v-for="entry in presentation.execution_audit.items.entries"
          :key="entry.key"
          :class="entry.class"
          v-bind="entry.attrs"
        >
          <div :class="entry.header.class">
            <span :class="entry.header.label.class">{{ entry.header.label.text }}</span>
            <span :class="entry.header.count.class">{{ entry.header.count.text }}</span>
          </div>
          <p v-if="entry.detail.visible" :class="entry.detail.class">{{ entry.detail.text }}</p>
        </div>
      </div>
    </section>

    <section
      v-if="presentation.review_origin.visible"
      :id="presentation.review_origin.id"
      :class="presentation.review_origin.class"
      v-bind="presentation.review_origin.attrs"
    >
      <div :class="presentation.review_origin.header.class">
        <span :class="presentation.review_origin.header.label.class">
          {{ presentation.review_origin.header.label.text }}
        </span>
        <a
          :href="presentation.review_origin.review_link.href"
          :class="presentation.review_origin.review_link.class"
          v-bind="presentation.review_origin.review_link.attrs"
        >
          <span
            :class="[
              presentation.review_origin.review_link.icon.name,
              presentation.review_origin.review_link.icon.class,
            ]"
          ></span>
          {{ presentation.review_origin.review_link.text }}
        </a>
      </div>
      <div
        v-if="presentation.review_origin.placements.visible"
        :class="presentation.review_origin.placements.class"
        v-bind="presentation.review_origin.placements.attrs"
      >
        <a
          v-for="link in presentation.review_origin.placements.links"
          :key="link.key"
          :href="link.href"
          :class="link.class"
          v-bind="link.attrs"
        >
          {{ link.text }}
        </a>
      </div>
    </section>

    <dl :class="presentation.details.class">
      <template v-for="row in presentation.details.rows" :key="row.key">
        <dt :class="row.label.class">{{ row.label.text }}</dt>
        <dd :class="row.value.class">{{ row.value.text }}</dd>
      </template>
    </dl>

    <section
      v-if="presentation.recovery.visible"
      :id="presentation.recovery.id"
      :class="presentation.recovery.class"
      v-bind="presentation.recovery.attrs"
    >
      <div :class="presentation.recovery.header.class">
        <span :class="presentation.recovery.header.label.class">
          {{ presentation.recovery.header.label.text }}
        </span>
        <span :class="presentation.recovery.header.resolved.class">
          {{ presentation.recovery.header.resolved.text }}
        </span>
      </div>

      <div
        v-if="presentation.recovery.review_origin.visible"
        :id="presentation.recovery.review_origin.id"
        :class="presentation.recovery.review_origin.class"
        v-bind="presentation.recovery.review_origin.attrs"
      >
        <span :class="presentation.recovery.review_origin.label.class">
          {{ presentation.recovery.review_origin.label.text }}
        </span>
        <a
          :href="presentation.recovery.review_origin.review_link.href"
          :class="presentation.recovery.review_origin.review_link.class"
          v-bind="presentation.recovery.review_origin.review_link.attrs"
        >
          <span
            :class="[
              presentation.recovery.review_origin.review_link.icon.name,
              presentation.recovery.review_origin.review_link.icon.class,
            ]"
          ></span>
          {{ presentation.recovery.review_origin.review_link.text }}
        </a>
      </div>

      <section
        :id="presentation.recovery.guidance.id"
        :class="presentation.recovery.guidance.class"
        v-bind="presentation.recovery.guidance.attrs"
      >
        <div :class="presentation.recovery.guidance.header.class">
          <span :class="presentation.recovery.guidance.header.label.class">
            {{ presentation.recovery.guidance.header.label.text }}
          </span>
          <span :class="presentation.recovery.guidance.header.next_action.class">
            {{ presentation.recovery.guidance.header.next_action.text }}
          </span>
        </div>
        <p :class="presentation.recovery.guidance.guidance.class">
          {{ presentation.recovery.guidance.guidance.text }}
        </p>
        <p
          v-if="presentation.recovery.guidance.retry_state.visible"
          :class="presentation.recovery.guidance.retry_state.class"
        >
          {{ presentation.recovery.guidance.retry_state.text }}
        </p>
        <p
          v-if="presentation.recovery.guidance.available_when.visible"
          :class="presentation.recovery.guidance.available_when.class"
        >
          {{ presentation.recovery.guidance.available_when.text }}
        </p>
      </section>

      <section
        v-if="presentation.recovery.failed_item_handoffs.visible"
        :id="presentation.recovery.failed_item_handoffs.id"
        :class="presentation.recovery.failed_item_handoffs.class"
        v-bind="presentation.recovery.failed_item_handoffs.attrs"
      >
        <div :class="presentation.recovery.failed_item_handoffs.header.class">
          <span :class="presentation.recovery.failed_item_handoffs.header.label.class">
            {{ presentation.recovery.failed_item_handoffs.header.label.text }}
          </span>
          <span :class="presentation.recovery.failed_item_handoffs.header.count.class">
            {{ presentation.recovery.failed_item_handoffs.header.count.text }}
          </span>
        </div>
        <div :class="presentation.recovery.failed_item_handoffs.links.class">
          <a
            v-for="link in presentation.recovery.failed_item_handoffs.links.entries"
            :key="link.key"
            :href="link.href"
            :class="link.class"
            v-bind="link.attrs"
          >
            <span :class="[link.icon.name, link.icon.class]"></span>
            {{ link.text }}
          </a>
        </div>
      </section>

      <section
        :id="presentation.recovery.execution_plan.id"
        :class="presentation.recovery.execution_plan.class"
        v-bind="presentation.recovery.execution_plan.attrs"
      >
        <div :class="presentation.recovery.execution_plan.header.class">
          <span :class="presentation.recovery.execution_plan.header.label.class">
            {{ presentation.recovery.execution_plan.header.label.text }}
          </span>
          <span :class="presentation.recovery.execution_plan.header.retry_count.class">
            {{ presentation.recovery.execution_plan.header.retry_count.text }}
          </span>
        </div>
        <dl :class="presentation.recovery.execution_plan.details.class">
          <template v-for="row in presentation.recovery.execution_plan.details.rows" :key="row.key">
            <dt :class="row.label.class">{{ row.label.text }}</dt>
            <dd :class="row.value.class">{{ row.value.text }}</dd>
          </template>
        </dl>

        <HistoricalWorkflowReplacementStatus
          :presentation="presentation.recovery.execution_plan.replacement_status"
        />

        <button
          v-if="presentation.recovery.execution_plan.retry_button.visible"
          :id="presentation.recovery.execution_plan.retry_button.id"
          :type="presentation.recovery.execution_plan.retry_button.type"
          :class="presentation.recovery.execution_plan.retry_button.class"
          v-bind="presentation.recovery.execution_plan.retry_button.attrs"
        >
          <span
            :class="[
              presentation.recovery.execution_plan.retry_button.icon.name,
              presentation.recovery.execution_plan.retry_button.icon.class,
            ]"
          ></span>
          {{ presentation.recovery.execution_plan.retry_button.text }}
        </button>

        <form
          v-if="presentation.recovery.execution_plan.advancement_form.visible"
          :id="presentation.recovery.execution_plan.advancement_form.id"
          :class="presentation.recovery.execution_plan.advancement_form.class"
          v-bind="presentation.recovery.execution_plan.advancement_form.attrs"
        >
          <input
            v-for="field in presentation.recovery.execution_plan.advancement_form.hidden_fields"
            :key="field.key"
            v-bind="field.attrs"
          />
          <div :class="presentation.recovery.execution_plan.advancement_form.header.class">
            <span :class="presentation.recovery.execution_plan.advancement_form.header.label.class">
              {{ presentation.recovery.execution_plan.advancement_form.header.label.text }}
            </span>
            <span :class="presentation.recovery.execution_plan.advancement_form.header.count.class">
              {{ presentation.recovery.execution_plan.advancement_form.header.count.text }}
            </span>
          </div>
          <p :class="presentation.recovery.execution_plan.advancement_form.preview.class">
            {{ presentation.recovery.execution_plan.advancement_form.preview.text }}
          </p>
          <button
            :id="presentation.recovery.execution_plan.advancement_form.button.id"
            :type="presentation.recovery.execution_plan.advancement_form.button.type"
            :class="presentation.recovery.execution_plan.advancement_form.button.class"
            v-bind="presentation.recovery.execution_plan.advancement_form.button.attrs"
          >
            <span :class="presentation.recovery.execution_plan.advancement_form.button.label.class">
              <span
                :class="[
                  presentation.recovery.execution_plan.advancement_form.button.label.icon.name,
                  presentation.recovery.execution_plan.advancement_form.button.label.icon.class,
                ]"
              ></span>
              {{ presentation.recovery.execution_plan.advancement_form.button.label.text }}
            </span>
            <span :class="presentation.recovery.execution_plan.advancement_form.button.count.class">
              {{ presentation.recovery.execution_plan.advancement_form.button.count.text }}
            </span>
          </button>
        </form>
      </section>

      <dl :class="presentation.recovery.details.class">
        <template v-for="row in presentation.recovery.details.rows" :key="row.key">
          <dt :class="row.label.class">{{ row.label.text }}</dt>
          <dd :class="row.value.class">{{ row.value.text }}</dd>
        </template>
      </dl>

      <template v-for="group in presentation.recovery.item_groups" :key="group.key">
        <div v-if="group.visible" :class="group.class" v-bind="group.attrs">
          <span :class="group.label.class">{{ group.label.text }}</span>
          <div v-for="item in group.items" :key="item.key" :class="item.class" v-bind="item.attrs">
            {{ item.text }}
          </div>
        </div>
      </template>

      <p :class="presentation.recovery.guidance_note.class">
        {{ presentation.recovery.guidance_note.text }}
      </p>
    </section>
  </div>
</template>
