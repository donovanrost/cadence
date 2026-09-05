<script setup>
import ClipboardButton from "./ClipboardButton.vue";
import CadencePopover from "./ui/reka/CadencePopover.vue";

defineProps({
  presentation: { type: Object, required: true },
});
</script>

<template>
  <div :id="presentation.root.id" :class="presentation.root.class" v-bind="presentation.root.attrs">
    <span :class="presentation.label.class">{{ presentation.label.text }}</span>
    <span :class="presentation.status.class">{{ presentation.status.text }}</span>
    <span :class="presentation.summary.class">{{ presentation.summary.text }}</span>
    <div :class="presentation.controls_class">
      <div :id="presentation.copy_host.id" :class="presentation.copy_host.class">
        <ClipboardButton v-bind="presentation.copy_props" />
      </div>
      <button
        :id="presentation.evidence.id"
        :type="presentation.evidence.type"
        :class="presentation.evidence.class"
        :title="presentation.evidence.title"
        :aria-label="presentation.evidence.aria_label"
        v-bind="presentation.evidence.attrs"
      >
        <span :class="[presentation.evidence.icon.name, presentation.evidence.icon.class]"></span>
      </button>
      <button
        :id="presentation.capture.id"
        :type="presentation.capture.type"
        :class="presentation.capture.class"
        :title="presentation.capture.title"
        :aria-label="presentation.capture.aria_label"
        v-bind="presentation.capture.attrs"
      >
        <span :class="[presentation.capture.icon.name, presentation.capture.icon.class]"></span>
      </button>
      <CadencePopover
        v-for="group in presentation.groups"
        :id="group.overlay.id"
        :key="group.key"
        :identity="group.overlay.id"
        :class="group.overlay.class"
        v-bind="group.overlay.attrs"
        side="bottom"
        align="end"
        :side-offset="8"
        :collision-padding="16"
      >
        <template #trigger="{ open }">
          <button
            :id="group.overlay.trigger.id"
            :type="group.overlay.trigger.type"
            :class="group.overlay.trigger.class"
            v-bind="group.overlay.trigger.attrs"
            :aria-expanded="
              open
                ? group.overlay.trigger.aria_expanded.open
                : group.overlay.trigger.aria_expanded.closed
            "
          >
            <span :class="group.badge.class" :title="group.badge.title" v-bind="group.badge.attrs">
              <span :class="[group.badge.icon.name, group.badge.icon.class]"></span>
              <span>{{ group.badge.label }}</span>
              <span :class="group.badge.count_class">{{ group.badge.count }}</span>
            </span>
          </button>
        </template>

        <template #content="{ open }">
          <section
            :id="group.overlay.panel.id"
            :class="group.overlay.panel.class"
            v-bind="group.overlay.panel.attrs"
            :hidden="!open"
          >
            <div :class="group.details.class">
              <div :class="group.details.heading.class">
                {{ group.details.heading.text }}
              </div>
              <div :class="group.details.items_class">
                <a
                  v-for="item in group.items"
                  :key="item.key"
                  :href="item.href"
                  :class="item.class"
                  v-bind="item.attrs"
                >
                  <span :class="item.title.class">{{ item.title.text }}</span>
                  <span :class="item.reason.class">{{ item.reason.text }}</span>
                </a>
              </div>
            </div>
          </section>
        </template>
      </CadencePopover>
    </div>
  </div>
</template>
