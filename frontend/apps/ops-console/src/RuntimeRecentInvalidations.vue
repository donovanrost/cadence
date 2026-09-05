<script setup lang="ts">
type DataAttrs = Record<string, string>;

type ElementPresentation = {
  class: string;
  data_attrs: DataAttrs;
};

type Action = {
  href: string;
  class: string;
  text: string;
  data_attrs: DataAttrs;
  icon: {
    name: string;
    class: string;
  };
};

type Field = {
  key: string;
  label: string;
  value: string;
  label_class: string;
  value_class: string;
  data_attrs: DataAttrs;
};

type Event = {
  id: string;
  class: string;
  data_attrs: DataAttrs;
  badges_class: string;
  badges: Array<{
    class: string;
    text: string;
  }>;
  actions: Action[];
  fields_class: string;
  fields: Field[];
};

type Presentation = {
  section: ElementPresentation;
  header: {
    class: string;
    heading: {
      class: string;
      text: string;
    };
    count: {
      class: string;
      value: number;
    };
  };
  list: {
    id: string;
    class: string;
  };
  events: Event[];
  empty: {
    visible: boolean;
    class: string;
    text: string;
  };
};

defineProps<{ presentation: Presentation }>();
</script>

<template>
  <section :class="presentation.section.class" v-bind="presentation.section.data_attrs">
    <div :class="presentation.header.class">
      <h3 :class="presentation.header.heading.class">
        {{ presentation.header.heading.text }}
      </h3>
      <span :class="presentation.header.count.class">
        {{ presentation.header.count.value }}
      </span>
    </div>
    <ol :id="presentation.list.id" :class="presentation.list.class">
      <li
        v-for="event in presentation.events"
        :id="event.id"
        :key="event.id"
        :class="event.class"
        v-bind="event.data_attrs"
      >
        <div :class="event.badges_class">
          <span v-for="badge in event.badges" :key="badge.class" :class="badge.class">
            {{ badge.text }}
          </span>
        </div>
        <a
          v-for="action in event.actions"
          :key="action.text"
          :href="action.href"
          :class="action.class"
          v-bind="action.data_attrs"
        >
          <span :class="[action.icon.name, action.icon.class]"></span> {{ action.text }}
        </a>
        <dl :class="event.fields_class">
          <template v-for="field in event.fields" :key="field.key">
            <dt :class="field.label_class">{{ field.label }}</dt>
            <dd :class="field.value_class" v-bind="field.data_attrs">
              {{ field.value }}
            </dd>
          </template>
        </dl>
      </li>
    </ol>
    <p v-if="presentation.empty.visible" :class="presentation.empty.class">
      {{ presentation.empty.text }}
    </p>
  </section>
</template>
