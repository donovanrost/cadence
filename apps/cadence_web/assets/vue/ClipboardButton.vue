<script setup>
import {computed, onUnmounted, ref} from "vue"

const props = defineProps({
  button_id: {type: String, required: true},
  clipboard_text: {type: String, default: ""},
  button_class: {type: String, default: ""},
  icon: {type: String, required: true},
  icon_class: {type: String, default: ""},
  label: {type: String, default: ""},
  title: {type: String, default: ""},
  aria_label: {type: String, default: ""},
  data_attrs: {type: Object, default: () => ({})}
})

const feedback = ref("")
let clearFeedbackTimer

const feedbackMessage = computed(() => {
  if (feedback.value === "copied") return "Copied to clipboard"
  if (feedback.value === "failed") return "Copy failed"
  return ""
})

const absoluteText = () => {
  const value = props.clipboard_text || window.location.pathname + window.location.search
  return new URL(value, window.location.origin).toString()
}

const copyWithFallback = (text) => {
  const textarea = document.createElement("textarea")
  textarea.value = text
  textarea.setAttribute("readonly", "readonly")
  textarea.style.position = "fixed"
  textarea.style.opacity = "0"
  document.body.appendChild(textarea)

  try {
    textarea.select()
    return document.execCommand("copy")
  } finally {
    textarea.remove()
  }
}

const markFeedback = (state) => {
  feedback.value = state
  if (clearFeedbackTimer !== undefined) clearTimeout(clearFeedbackTimer)

  clearFeedbackTimer = setTimeout(() => {
    feedback.value = ""
    clearFeedbackTimer = undefined
  }, 1500)
}

const copy = async () => {
  let text

  try {
    text = absoluteText()
  } catch (_error) {
    markFeedback("failed")
    return
  }

  try {
    await navigator.clipboard.writeText(text)
    markFeedback("copied")
  } catch (_error) {
    try {
      markFeedback(copyWithFallback(text) === false ? "failed" : "copied")
    } catch (_fallbackError) {
      markFeedback("failed")
    }
  }
}

onUnmounted(() => {
  if (clearFeedbackTimer !== undefined) clearTimeout(clearFeedbackTimer)
})
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
  <span class="sr-only" role="status" aria-live="polite" aria-atomic="true">
    {{ feedbackMessage }}
  </span>
</template>
