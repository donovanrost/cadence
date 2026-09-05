<script setup>
import ClipboardButton from "./ClipboardButton.vue";

defineProps({
  presentation: { type: Object, required: true },
});
</script>

<template>
  <section v-bind="presentation.root.attrs">
    <div v-bind="presentation.header.attrs">
      <div v-bind="presentation.header.badges.attrs">
        <span
          v-for="badge in presentation.header.badges.items"
          :key="badge.key"
          v-bind="badge.attrs"
        >
          {{ badge.text }}
        </span>
      </div>
      <p v-if="presentation.header.message" v-bind="presentation.header.message.attrs">
        {{ presentation.header.message.text }}
      </p>
    </div>

    <div v-bind="presentation.actions.attrs">
      <div v-bind="presentation.actions.copy.host.attrs">
        <ClipboardButton v-bind="presentation.actions.copy.props" />
      </div>

      <a v-for="action in presentation.actions.dashboard" :key="action.key" v-bind="action.attrs">
        <span :class="[action.icon.name, action.icon.class]"></span> {{ action.text }}
      </a>

      <a v-if="presentation.actions.health" v-bind="presentation.actions.health.attrs">
        <span
          :class="[presentation.actions.health.icon.name, presentation.actions.health.icon.class]"
        ></span>
        {{ presentation.actions.health.text }}
      </a>
    </div>

    <section v-if="presentation.subject" v-bind="presentation.subject.attrs">
      <h3 v-bind="presentation.subject.heading.attrs">
        {{ presentation.subject.heading.text }}
      </h3>
      <dl v-bind="presentation.subject.list.attrs">
        <template v-for="row in presentation.subject.list.rows" :key="row.key">
          <dt v-bind="row.label.attrs">{{ row.label.text }}</dt>
          <dd v-bind="row.value.attrs">{{ row.value.text }}</dd>
        </template>
      </dl>
    </section>

    <section v-if="presentation.details" v-bind="presentation.details.attrs">
      <h3 v-bind="presentation.details.heading.attrs">
        {{ presentation.details.heading.text }}
      </h3>
      <dl v-bind="presentation.details.list.attrs">
        <template v-for="row in presentation.details.list.rows" :key="row.key">
          <dt v-bind="row.label.attrs">{{ row.label.text }}</dt>
          <dd v-bind="row.value.attrs">{{ row.value.text }}</dd>
        </template>
      </dl>
    </section>

    <section v-if="presentation.evidence.items.length" v-bind="presentation.evidence.root.attrs">
      <h3 v-bind="presentation.evidence.heading.attrs">
        {{ presentation.evidence.heading.text }}
      </h3>
      <div v-bind="presentation.evidence.list.attrs">
        <component
          :is="item.tag"
          v-for="item in presentation.evidence.items"
          :key="item.key"
          v-bind="item.attrs"
        >
          <template v-for="row in item.rows" :key="row.key">
            <span v-bind="row.label.attrs">{{ row.label.text }}</span>
            <span v-bind="row.value.attrs">{{ row.value.text }}</span>
          </template>
        </component>
      </div>
    </section>
    <p v-else v-bind="presentation.evidence.empty.attrs">
      {{ presentation.evidence.empty.text }}
    </p>

    <section
      v-if="presentation.data_links.items.length"
      v-bind="presentation.data_links.root.attrs"
    >
      <h3 v-bind="presentation.data_links.heading.attrs">
        {{ presentation.data_links.heading.text }}
      </h3>
      <div v-bind="presentation.data_links.list.attrs">
        <button v-for="link in presentation.data_links.items" :key="link.key" v-bind="link.attrs">
          <template v-for="row in link.rows" :key="row.key">
            <span v-bind="row.label.attrs">{{ row.label.text }}</span>
            <span v-bind="row.value.attrs">{{ row.value.text }}</span>
          </template>
        </button>
      </div>
    </section>
    <p v-else v-bind="presentation.data_links.empty.attrs">
      {{ presentation.data_links.empty.text }}
    </p>
  </section>
</template>
