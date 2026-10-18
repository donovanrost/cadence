<script setup lang="ts">
import CadenceDetailsFrame from "./CadenceDetailsFrame.vue";
import CadenceClipboardButton from "./CadenceClipboardButton.vue";

withDefaults(
  defineProps<{
    id: string;
    summary?: string;
    context: string;
    items: readonly Readonly<{
      label: string;
      value: string | null;
      href?: string | null;
    }>[];
  }>(),
  { summary: "Technical details" },
);
</script>

<template>
  <CadenceDetailsFrame :id="id" class="text-sm font-normal">
    <summary
      class="cursor-pointer rounded text-base-content/70 hover:text-primary focus-visible:outline-2 focus-visible:outline-primary"
    >
      {{ summary }}<span class="sr-only"> for {{ context }}</span>
    </summary>
    <dl class="mt-3 space-y-3">
      <div v-for="(item, index) in items" :key="item.label" class="space-y-1">
        <dt class="text-xs text-base-content/70">{{ item.label }}</dt>
        <dd class="space-y-1">
          <a
            v-if="item.href && item.value !== null"
            :href="item.href"
            class="block break-all font-mono text-xs text-primary hover:underline"
            >{{ item.value }}</a
          >
          <span v-else class="block break-all font-mono text-xs">{{
            item.value ?? "Not available"
          }}</span>
          <div
            v-if="item.value !== null && item.value !== ''"
            class="flex flex-wrap items-center gap-2"
          >
            <CadenceClipboardButton
              :button_id="`${id}-copy-${index}`"
              :clipboard_text="item.value"
              copy_as="text"
              button_class="btn btn-ghost btn-xs gap-1"
              icon="hero-clipboard-document"
              icon_class="h-3 w-3"
              label="Copy"
              :aria_label="`Copy ${item.label} for ${context}`"
              feedback_class="text-xs text-base-content/70"
            />
          </div>
        </dd>
      </div>
    </dl>
  </CadenceDetailsFrame>
</template>
