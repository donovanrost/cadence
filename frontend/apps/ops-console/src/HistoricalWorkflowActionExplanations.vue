<script setup>
defineProps({
  presentation: {type: Object, required: true}
})
</script>

<template>
  <section
    :id="presentation.root.id"
    :class="presentation.root.class"
  >
    <div :class="presentation.header.class">
      <h4 :class="presentation.header.heading.class">{{ presentation.header.heading.text }}</h4>
      <span :class="presentation.header.count.class">{{ presentation.header.count.text }}</span>
    </div>
    <div :class="presentation.items_container.class">
      <div
        v-for="item in presentation.items"
        :key="item.key"
        :class="item.class"
        v-bind="item.attrs"
      >
        <div :class="item.header.class">
          <span :class="item.label.class">{{ item.label.text }}</span>
          <span :class="item.reason.class">{{ item.reason.text }}</span>
        </div>
        <p :class="item.explanation.class">{{ item.explanation.text }}</p>
        <p
          v-if="item.state.visible"
          :class="item.state.class"
        >{{ item.state.text }}</p>
        <p
          v-if="item.available_when.visible"
          :class="item.available_when.class"
        >{{ item.available_when.text }}</p>
      </div>
    </div>
  </section>
</template>
