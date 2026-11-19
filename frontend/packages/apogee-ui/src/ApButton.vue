<script setup lang="ts">
import { computed } from "vue";
import { RouterLink, type RouteLocationRaw } from "vue-router";

const props = withDefaults(
  defineProps<{
    variant?: "primary" | "secondary" | "ghost" | "danger" | undefined;
    size?: "compact" | "standard" | "commit" | undefined;
    /** Renders a RouterLink when set. */
    to?: RouteLocationRaw | undefined;
    /** Renders a plain anchor (outside the SPA) when set. */
    href?: string | undefined;
    type?: "button" | "submit" | "reset" | undefined;
    disabled?: boolean | undefined;
    /** Why it's disabled; required in spirit: never disable a commit action silently. */
    disabledReason?: string | undefined;
  }>(),
  { variant: "secondary", size: "standard", type: "button", disabled: false },
);

const emit = defineEmits<{ click: [event: MouseEvent] }>();
const reasonId = `ap-btn-reason-${Math.random().toString(36).slice(2, 10)}`;

/** Disabled buttons stay focusable (aria-disabled) so the reason can be read; clicks are dropped. */
function onClick(event: MouseEvent) {
  if (props.disabled) {
    event.preventDefault();
    return;
  }
  emit("click", event);
}

const variantClasses = {
  primary: "bg-action text-on-action border-action hover:bg-bright hover:text-on-action",
  secondary: "bg-raised text-readout border-line hover:bg-raised-hi hover:text-readout",
  ghost: "bg-transparent text-text-3 border-transparent hover:text-readout hover:bg-raised",
  danger: "bg-crit-deep text-crit-text border-crit-line hover:text-crit-text hover:bg-crit-deep",
} as const satisfies Record<NonNullable<typeof props.variant>, string>;

const sizeClasses = {
  compact: "h-8 px-3 text-md tracking-btn max-md:hit-44",
  standard: "h-[38px] px-[18px] text-base tracking-tag max-md:hit-44",
  // Mobile.md: primary actions are ≥ 48px on phones.
  commit: "h-[46px] px-6 text-[15px] tracking-tag max-md:h-12",
} as const satisfies Record<NonNullable<typeof props.size>, string>;

const classes = computed(() => [
  "inline-flex items-center justify-center gap-2 border font-display font-semibold uppercase whitespace-nowrap no-underline cursor-pointer",
  sizeClasses[props.size],
  props.disabled
    ? "bg-panel text-text-off border-hairline cursor-not-allowed"
    : variantClasses[props.variant],
]);
</script>

<template>
  <RouterLink v-if="to !== undefined && !disabled" :to="to" :class="classes" @click="onClick">
    <slot />
  </RouterLink>
  <a v-else-if="href !== undefined && !disabled" :href="href" :class="classes">
    <slot />
  </a>
  <button
    v-else
    :type="disabled ? 'button' : type"
    :aria-disabled="disabled ? 'true' : undefined"
    :aria-describedby="disabled && disabledReason ? reasonId : undefined"
    :title="disabled ? disabledReason : undefined"
    :class="classes"
    @click="onClick"
  >
    <slot />
    <span v-if="disabled && disabledReason" :id="reasonId" aria-hidden="true" class="sr-only">{{
      disabledReason
    }}</span>
  </button>
</template>
