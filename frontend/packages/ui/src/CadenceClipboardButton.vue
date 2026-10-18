<script setup lang="ts">
import { computed, onUnmounted, ref } from "vue";

const props = withDefaults(
  defineProps<{
    button_id: string;
    clipboard_text?: string;
    copy_as?: "url" | "text";
    feedback_class?: string;
    button_class?: string;
    icon: string;
    icon_class?: string;
    label?: string;
    title?: string;
    aria_label?: string;
    data_attrs?: Record<string, unknown>;
  }>(),
  {
    clipboard_text: "",
    copy_as: "url",
    feedback_class: "sr-only",
    button_class: "",
    icon_class: "",
    label: "",
    title: "",
    aria_label: "",
    data_attrs: () => ({}),
  },
);

const feedback = ref<"" | "copied" | "failed">("");
let clearFeedbackTimer: ReturnType<typeof setTimeout> | undefined;
let active = true;

const feedbackMessage = computed(() => {
  if (feedback.value === "copied") return "Copied to clipboard";
  if (feedback.value === "failed") return "Copy failed";
  return "";
});

const absoluteText = () => {
  if (props.copy_as === "text") return props.clipboard_text;
  const value = props.clipboard_text || window.location.pathname + window.location.search;
  return new URL(value, window.location.origin).toString();
};

const copyWithFallback = (text: string) => {
  const previouslyFocused = document.activeElement;
  const textarea = document.createElement("textarea");
  textarea.value = text;
  textarea.setAttribute("readonly", "readonly");
  textarea.style.position = "fixed";
  textarea.style.opacity = "0";
  document.body.appendChild(textarea);

  try {
    textarea.select();
    return document.execCommand("copy");
  } finally {
    textarea.remove();
    if (previouslyFocused instanceof HTMLElement) previouslyFocused.focus();
  }
};

const markFeedback = (state: "copied" | "failed") => {
  if (!active) return;
  feedback.value = state;
  if (clearFeedbackTimer !== undefined) clearTimeout(clearFeedbackTimer);

  clearFeedbackTimer = setTimeout(() => {
    feedback.value = "";
    clearFeedbackTimer = undefined;
  }, 1500);
};

const copy = async () => {
  let text;

  try {
    text = absoluteText();
  } catch (_error) {
    markFeedback("failed");
    return;
  }

  try {
    await navigator.clipboard.writeText(text);
    markFeedback("copied");
  } catch (_error) {
    try {
      markFeedback(copyWithFallback(text) === false ? "failed" : "copied");
    } catch (_fallbackError) {
      markFeedback("failed");
    }
  }
};

onUnmounted(() => {
  active = false;
  if (clearFeedbackTimer !== undefined) clearTimeout(clearFeedbackTimer);
});
</script>

<template>
  <button
    :id="props.button_id"
    type="button"
    :class="props.button_class"
    :title="props.title || undefined"
    :aria-label="props.aria_label || undefined"
    data-clipboard-button
    :data-clipboard-text="props.clipboard_text || undefined"
    :data-clipboard-copied="feedback === 'copied' ? 'true' : undefined"
    :data-clipboard-failed="feedback === 'failed' ? 'true' : undefined"
    v-bind="props.data_attrs"
    @click="copy"
  >
    <span :class="[props.icon, props.icon_class]"></span> {{ props.label }}
  </button>
  <span :class="props.feedback_class" role="status" aria-live="polite" aria-atomic="true">
    {{ feedbackMessage }}
  </span>
</template>
