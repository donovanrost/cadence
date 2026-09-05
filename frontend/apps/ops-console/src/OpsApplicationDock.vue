<script setup>
defineProps({
  presentation: {type: Object, required: true}
})
</script>

<template>
  <details
    v-bind="presentation.root.attrs"
    :class="presentation.root.class"
  >
    <summary :class="presentation.summary.class">
      <span :class="presentation.label.class">{{ presentation.label.text }}</span>
      <nav
        v-bind="presentation.navigation.attrs"
        :class="presentation.navigation.class"
      >
        <button
          v-for="tab in presentation.navigation.tabs"
          :key="tab.key"
          v-bind="tab.attrs"
          :class="tab.class"
        >{{ tab.label }}</button>
      </nav>
      <span :class="presentation.chevron.class"></span>
    </summary>

    <div
      v-bind="presentation.panel.attrs"
      :class="presentation.panel.class"
    >
      <div :class="presentation.panel.message.class">{{ presentation.panel.message.text }}</div>
    </div>
  </details>
</template>
