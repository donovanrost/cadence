import { computed, readonly, ref } from "vue";
import { decoders as d, isError, request, type ApiError } from "@/api/index.ts";
import type { Session } from "@/api/session.ts";
import { formatCountdown } from "@/ui";

/**
 * L6 admin mode (Auth.md, api-ops shape 11-13): a password step-up for platform administration,
 * for the server's TTL. The session snapshot is static, so admin mode lives here: seeded from the
 * bootstrap, then moved by enter/leave. `expiresAt` null with `on` true means the server said
 * admin mode is on without a time (an older server): no countdown, still on.
 */
const on = ref(false);
const expiresAt = ref<number | null>(null);

export function seedAdminMode(session: Readonly<Session>) {
  on.value = session.admin_mode;
  expiresAt.value = session.admin_mode_expires_at
    ? Date.parse(session.admin_mode_expires_at)
    : null;
}

const enterReader = d.object({ expires_at: d.timestamp });
const emptyReader = (value: unknown) => value;

export type EnterOutcome =
  | { ok: true }
  | { ok: false; reason: "wrong_password" | "throttled" | "forbidden" | "other"; error: ApiError };

export async function enterAdminMode(password: string): Promise<EnterOutcome> {
  const result = await request("/session/admin-mode", enterReader, {
    method: "POST",
    body: { password },
  });
  if (result.ok) {
    on.value = true;
    expiresAt.value = Date.parse(result.value.expires_at);
    return { ok: true };
  }
  const e = result.error;
  const reason = isError(e, "password_incorrect")
    ? "wrong_password"
    : isError(e, "too_many_attempts")
      ? "throttled"
      : e.kind === "forbidden"
        ? "forbidden"
        : "other";
  return { ok: false, reason, error: e };
}

/** Leaving is immediate and idempotent (204); the local state ends even if the call fails. */
export async function leaveAdminMode(): Promise<void> {
  on.value = false;
  expiresAt.value = null;
  await request("/session/admin-mode", emptyReader, { method: "DELETE" });
}

/** Active now, the chip's `ADMIN MODE · 52:10`, and whether it's under 5 minutes. */
export function useAdminMode(now: () => Date) {
  const active = computed(() => {
    if (!on.value) return false;
    return expiresAt.value === null || expiresAt.value > now().getTime();
  });
  const remaining = computed(() =>
    active.value && expiresAt.value !== null
      ? formatCountdown(new Date(expiresAt.value), now()).replace(/^T−/, "")
      : null,
  );
  const ending = computed(
    () =>
      active.value && expiresAt.value !== null && expiresAt.value - now().getTime() < 5 * 60_000,
  );
  return {
    active,
    remaining,
    ending,
    expiresAt: readonly(expiresAt),
  };
}
