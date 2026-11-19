<script setup lang="ts" generic="Value extends string">
/**
 * `choice`: radio semantics, choosing a value (white fill when selected).
 * `tabs`: switching views or filters (raised + inset white bottom bar when active).
 * `micro`: chart window inside a panel.
 * For navigation between routes use ApTabLinks instead (links, not tabs).
 */
export type ApSegment<V extends string> = Readonly<{ value: V; label: string; count?: number }>;

const props = withDefaults(
  defineProps<{
    options: readonly ApSegment<Value>[];
    modelValue: Value;
    label: string;
    variant?: "choice" | "tabs" | "micro" | undefined;
  }>(),
  { variant: "choice" },
);

const emit = defineEmits<{ "update:modelValue": [value: Value] }>();

function move(event: KeyboardEvent, index: number) {
  const count = props.options.length;
  let next: number;
  switch (event.key) {
    case "ArrowRight":
    case "ArrowDown":
      next = (index + 1) % count;
      break;
    case "ArrowLeft":
    case "ArrowUp":
      next = (index - 1 + count) % count;
      break;
    case "Home":
      next = 0;
      break;
    case "End":
      next = count - 1;
      break;
    default:
      return;
  }
  event.preventDefault();
  const option = props.options[next];
  if (!option) return;
  emit("update:modelValue", option.value);
  const group = (event.currentTarget as HTMLElement | null)?.parentElement;
  const target = group?.children.item(next);
  if (target instanceof HTMLElement) target.focus();
}
</script>

<template>
  <div
    :role="variant === 'tabs' ? 'tablist' : 'radiogroup'"
    :aria-label="label"
    class="inline-flex items-stretch"
    :class="
      variant === 'choice'
        ? 'border border-line'
        : variant === 'tabs'
          ? 'border-b border-hairline'
          : 'gap-px'
    "
  >
    <button
      v-for="(option, index) in options"
      :key="option.value"
      type="button"
      :role="variant === 'tabs' ? 'tab' : 'radio'"
      :aria-checked="variant === 'tabs' ? undefined : option.value === modelValue"
      :aria-selected="variant === 'tabs' ? option.value === modelValue : undefined"
      :tabindex="option.value === modelValue ? 0 : -1"
      class="flex cursor-pointer items-center gap-2 border-0 whitespace-nowrap max-md:hit-44"
      :class="{
        'h-[30px] px-3 font-display text-md font-semibold tracking-title uppercase':
          variant === 'choice',
        'bg-action text-on-action': variant === 'choice' && option.value === modelValue,
        'bg-transparent text-text-3 hover:text-readout':
          variant !== 'micro' && option.value !== modelValue,
        'h-9 border-r border-hairline px-4 font-display text-md font-semibold tracking-tag uppercase last:border-r-0':
          variant === 'tabs',
        'bg-raised text-readout shadow-[inset_0_-2px_0_var(--color-readout)]':
          variant === 'tabs' && option.value === modelValue,
        'h-[26px] px-2 font-mono text-xs': variant === 'micro',
        'bg-hairline text-readout': variant === 'micro' && option.value === modelValue,
        'bg-transparent text-text-4 hover:text-readout':
          variant === 'micro' && option.value !== modelValue,
      }"
      @click="emit('update:modelValue', option.value)"
      @keydown="move($event, index)"
    >
      {{ option.label
      }}<span v-if="option.count !== undefined" class="font-mono text-xs">{{ option.count }}</span>
    </button>
  </div>
</template>
