<script setup>
defineProps({
  presentation: { type: Object, required: true },
});
</script>

<template>
  <div v-bind="presentation.root.attrs">
    <div v-bind="presentation.pointers.attrs">
      <div v-for="pointer in presentation.pointers.items" :key="pointer.key" v-bind="pointer.attrs">
        <div v-bind="pointer.label.attrs">{{ pointer.label.text }}</div>
        <div v-bind="pointer.value.attrs">{{ pointer.value.text }}</div>
      </div>
    </div>

    <section v-bind="presentation.versions.section.attrs">
      <div v-bind="presentation.versions.header.attrs">
        <h3 v-bind="presentation.versions.header.heading.attrs">
          {{ presentation.versions.header.heading.text }}
        </h3>
        <span v-bind="presentation.versions.header.count.attrs">
          {{ presentation.versions.header.count.text }}
        </span>
      </div>

      <ol v-bind="presentation.versions.list.attrs">
        <li
          v-for="version in presentation.versions.list.rows"
          :key="version.key"
          v-bind="version.attrs"
        >
          <div v-bind="version.layout.attrs">
            <div v-bind="version.content.attrs">
              <div v-bind="version.identity.attrs">
                <span v-bind="version.identity.version.attrs">
                  {{ version.identity.version.text }}
                </span>
                <span v-bind="version.identity.snapshot.attrs">
                  {{ version.identity.snapshot.text }}
                </span>
                <span
                  v-for="pointer in version.identity.pointers"
                  :key="pointer.key"
                  v-bind="pointer.attrs"
                >
                  {{ pointer.text }}
                </span>
              </div>

              <dl v-bind="version.details.attrs">
                <template v-for="detail in version.details.rows" :key="detail.key">
                  <dt v-bind="detail.label.attrs">{{ detail.label.text }}</dt>
                  <dd v-bind="detail.value.attrs">{{ detail.value.text }}</dd>
                </template>
              </dl>

              <p v-if="version.summary.visible" v-bind="version.summary.attrs">
                {{ version.summary.text }}
              </p>
            </div>

            <div v-bind="version.actions.attrs">
              <button
                v-for="button in version.actions.buttons"
                :key="button.key"
                v-bind="button.attrs"
              >
                <span v-bind="button.icon.attrs"></span>
                {{ button.text }}
              </button>
            </div>
          </div>
        </li>
      </ol>

      <p v-if="presentation.versions.empty.visible" v-bind="presentation.versions.empty.attrs">
        {{ presentation.versions.empty.text }}
      </p>
    </section>
  </div>
</template>
