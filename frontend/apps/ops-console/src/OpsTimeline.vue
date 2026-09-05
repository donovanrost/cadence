<script setup lang="ts">
import { reactive, watch } from "vue";
import ClipboardButton from "./ClipboardButton.vue";

type RawAttrs = Record<string, string>;

type ElementPresentation = {
  attrs: RawAttrs;
};

type TextPresentation = ElementPresentation & {
  text: string;
};

type FilterValues = {
  category: string;
  kind: string;
  severity: string;
  spacecraft_id: string;
  from: string;
  to: string;
};

type FilterField = {
  key: keyof FilterValues;
  type: "select" | "text";
  wrapper: ElementPresentation;
  label: ElementPresentation;
  label_text: TextPresentation;
  control: ElementPresentation;
  options: Array<{ label: string; value: string }>;
};

type NavigationLink = TextPresentation & {
  icon: ElementPresentation;
};

type SelectedEvent = ElementPresentation & {
  header: ElementPresentation & {
    content: ElementPresentation;
    kind: TextPresentation;
    title: TextPresentation;
    clear: ElementPresentation & { icon: ElementPresentation };
  };
  copy: {
    host_attrs: RawAttrs;
    button_id: string;
    clipboard_text: string;
    button_class: string;
    icon: string;
    icon_class: string;
    label: string;
  };
  rows: ElementPresentation & {
    items: Array<{
      label: TextPresentation;
      value: TextPresentation;
    }>;
  };
  investigation: ElementPresentation & {
    title: TextPresentation;
    links: ElementPresentation & {
      owner: NavigationLink | null;
      explore: NavigationLink | null;
    };
  };
};

type Presentation = {
  root: ElementPresentation;
  container: ElementPresentation;
  header: ElementPresentation & {
    content: ElementPresentation;
    eyebrow: TextPresentation;
    title: TextPresentation;
    description: TextPresentation;
    return_link: NavigationLink | null;
  };
  filters: ElementPresentation & {
    values: FilterValues;
    fields: FilterField[];
    submit: TextPresentation & { icon: ElementPresentation };
  };
  body: ElementPresentation & {
    timeline: {
      section: ElementPresentation;
      header: ElementPresentation & { columns: string[] };
      stream: ElementPresentation & { empty: TextPresentation };
    };
    detail: ElementPresentation & {
      empty:
        | (ElementPresentation & {
            content: ElementPresentation;
            icon: ElementPresentation;
            copy: TextPresentation;
          })
        | null;
      selected: SelectedEvent | null;
    };
  };
};

type TimelineEvent = {
  __dom_id: string;
  mission_event_id: string;
  attrs: RawAttrs;
  occurred: TextPresentation;
  category: TextPresentation;
  event: ElementPresentation & {
    title: TextPresentation;
    summary: TextPresentation;
  };
  subject: TextPresentation;
};

const props = defineProps<{
  presentation: Presentation;
  timeline_events: TimelineEvent[];
}>();

const emit = defineEmits<{
  apply_timeline_filters: [payload: { timeline: FilterValues }];
  clear_timeline_selection: [payload: Record<string, never>];
}>();

const filterValues = reactive<FilterValues>({ ...props.presentation.filters.values });

watch(
  () => props.presentation.filters.values,
  (values) => Object.assign(filterValues, values),
  { deep: true },
);

const updateFilter = (key: keyof FilterValues, event: Event) => {
  filterValues[key] = (event.target as HTMLInputElement | HTMLSelectElement).value;
};

const applyFilters = () => {
  emit("apply_timeline_filters", {
    timeline: {
      category: filterValues.category,
      kind: filterValues.kind,
      severity: filterValues.severity,
      spacecraft_id: filterValues.spacecraft_id,
      from: filterValues.from,
      to: filterValues.to,
    },
  });
};

const clearSelection = () => emit("clear_timeline_selection", {});
</script>

<template>
  <main v-bind="props.presentation.root.attrs">
    <div v-bind="props.presentation.container.attrs">
      <header v-bind="props.presentation.header.attrs">
        <div v-bind="props.presentation.header.content.attrs">
          <p v-bind="props.presentation.header.eyebrow.attrs">
            {{ props.presentation.header.eyebrow.text }}
          </p>
          <h1 v-bind="props.presentation.header.title.attrs">
            {{ props.presentation.header.title.text }}
          </h1>
          <p v-bind="props.presentation.header.description.attrs">
            {{ props.presentation.header.description.text }}
          </p>
        </div>
        <a
          v-if="props.presentation.header.return_link"
          v-bind="props.presentation.header.return_link.attrs"
        >
          <span v-bind="props.presentation.header.return_link.icon.attrs"></span>
          {{ props.presentation.header.return_link.text }}
        </a>
      </header>

      <form v-bind="props.presentation.filters.attrs" @submit.prevent="applyFilters">
        <div
          v-for="field in props.presentation.filters.fields"
          :key="field.key"
          v-bind="field.wrapper.attrs"
        >
          <label v-bind="field.label.attrs">
            <span v-bind="field.label_text.attrs">{{ field.label_text.text }}</span>
            <select
              v-if="field.type === 'select'"
              v-bind="field.control.attrs"
              :value="filterValues[field.key]"
              @change="updateFilter(field.key, $event)"
            >
              <option v-for="option in field.options" :key="option.value" :value="option.value">
                {{ option.label }}
              </option>
            </select>
            <input
              v-else
              v-bind="field.control.attrs"
              :value="filterValues[field.key]"
              @input="updateFilter(field.key, $event)"
            />
          </label>
        </div>
        <button v-bind="props.presentation.filters.submit.attrs">
          <span v-bind="props.presentation.filters.submit.icon.attrs"></span>
          {{ props.presentation.filters.submit.text }}
        </button>
      </form>

      <div v-bind="props.presentation.body.attrs">
        <section v-bind="props.presentation.body.timeline.section.attrs">
          <div v-bind="props.presentation.body.timeline.header.attrs">
            <span v-for="column in props.presentation.body.timeline.header.columns" :key="column">{{
              column
            }}</span>
          </div>
          <div v-bind="props.presentation.body.timeline.stream.attrs">
            <div v-bind="props.presentation.body.timeline.stream.empty.attrs">
              {{ props.presentation.body.timeline.stream.empty.text }}
            </div>
            <a
              v-for="timelineEvent in props.timeline_events"
              :id="timelineEvent.__dom_id"
              :key="timelineEvent.__dom_id"
              v-bind="timelineEvent.attrs"
            >
              <time v-bind="timelineEvent.occurred.attrs">{{ timelineEvent.occurred.text }}</time>
              <span v-bind="timelineEvent.category.attrs">{{ timelineEvent.category.text }}</span>
              <span v-bind="timelineEvent.event.attrs">
                <span v-bind="timelineEvent.event.title.attrs">{{
                  timelineEvent.event.title.text
                }}</span>
                <span v-bind="timelineEvent.event.summary.attrs">
                  {{ timelineEvent.event.summary.text }}
                </span>
              </span>
              <span v-bind="timelineEvent.subject.attrs">{{ timelineEvent.subject.text }}</span>
            </a>
          </div>
        </section>

        <aside v-bind="props.presentation.body.detail.attrs">
          <div
            v-if="props.presentation.body.detail.empty"
            v-bind="props.presentation.body.detail.empty.attrs"
          >
            <div v-bind="props.presentation.body.detail.empty.content.attrs">
              <span v-bind="props.presentation.body.detail.empty.icon.attrs"></span>
              <p v-bind="props.presentation.body.detail.empty.copy.attrs">
                {{ props.presentation.body.detail.empty.copy.text }}
              </p>
            </div>
          </div>

          <div
            v-if="props.presentation.body.detail.selected"
            v-bind="props.presentation.body.detail.selected.attrs"
          >
            <div v-bind="props.presentation.body.detail.selected.header.attrs">
              <div v-bind="props.presentation.body.detail.selected.header.content.attrs">
                <p v-bind="props.presentation.body.detail.selected.header.kind.attrs">
                  {{ props.presentation.body.detail.selected.header.kind.text }}
                </p>
                <h2 v-bind="props.presentation.body.detail.selected.header.title.attrs">
                  {{ props.presentation.body.detail.selected.header.title.text }}
                </h2>
              </div>
              <button
                v-bind="props.presentation.body.detail.selected.header.clear.attrs"
                @click="clearSelection"
              >
                <span
                  v-bind="props.presentation.body.detail.selected.header.clear.icon.attrs"
                ></span>
              </button>
            </div>

            <div v-bind="props.presentation.body.detail.selected.copy.host_attrs">
              <ClipboardButton
                :button_id="props.presentation.body.detail.selected.copy.button_id"
                :clipboard_text="props.presentation.body.detail.selected.copy.clipboard_text"
                :button_class="props.presentation.body.detail.selected.copy.button_class"
                :icon="props.presentation.body.detail.selected.copy.icon"
                :icon_class="props.presentation.body.detail.selected.copy.icon_class"
                :label="props.presentation.body.detail.selected.copy.label"
              />
            </div>

            <dl v-bind="props.presentation.body.detail.selected.rows.attrs">
              <template
                v-for="row in props.presentation.body.detail.selected.rows.items"
                :key="row.label.text"
              >
                <dt v-bind="row.label.attrs">{{ row.label.text }}</dt>
                <dd v-bind="row.value.attrs">{{ row.value.text }}</dd>
              </template>
            </dl>

            <section v-bind="props.presentation.body.detail.selected.investigation.attrs">
              <h3 v-bind="props.presentation.body.detail.selected.investigation.title.attrs">
                {{ props.presentation.body.detail.selected.investigation.title.text }}
              </h3>
              <div v-bind="props.presentation.body.detail.selected.investigation.links.attrs">
                <a
                  v-if="props.presentation.body.detail.selected.investigation.links.owner"
                  v-bind="props.presentation.body.detail.selected.investigation.links.owner.attrs"
                >
                  <span
                    v-bind="
                      props.presentation.body.detail.selected.investigation.links.owner.icon.attrs
                    "
                  ></span>
                  {{ props.presentation.body.detail.selected.investigation.links.owner.text }}
                </a>
                <a
                  v-if="props.presentation.body.detail.selected.investigation.links.explore"
                  v-bind="props.presentation.body.detail.selected.investigation.links.explore.attrs"
                >
                  <span
                    v-bind="
                      props.presentation.body.detail.selected.investigation.links.explore.icon.attrs
                    "
                  ></span>
                  {{ props.presentation.body.detail.selected.investigation.links.explore.text }}
                </a>
              </div>
            </section>
          </div>
        </aside>
      </div>
    </div>
  </main>
</template>
