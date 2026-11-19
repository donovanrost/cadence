import { onScopeDispose, shallowRef } from "vue";
import { setCsrfToken, type ApiError } from "@/api/http.ts";
import { fetchSession, type Session } from "@/api/session.ts";

export type BootState =
  | { status: "loading" }
  | { status: "ready"; session: Readonly<Session> }
  | { status: "failed"; error: ApiError };

/**
 * Loads the session bootstrap once for the app's lifetime. 401 leaves for the console sign-in
 * (L5) with return_to; App sends a session with no organizations to auth.no-org.
 */
export function useBootstrap() {
  const state = shallowRef<BootState>({ status: "loading" });
  const controller = new AbortController();
  onScopeDispose(() => controller.abort());

  async function load() {
    state.value = { status: "loading" };
    try {
      const result = await fetchSession(controller.signal);
      if (result.ok) {
        setCsrfToken(result.value.csrf_token);
        state.value = { status: "ready", session: result.value };
      } else if (result.error.kind === "unauthenticated") {
        const back = window.location.pathname + window.location.search;
        window.location.assign(`/console/sign-in?return_to=${encodeURIComponent(back)}`);
      } else {
        state.value = { status: "failed", error: result.error };
      }
    } catch (error) {
      if (controller.signal.aborted) return;
      state.value = {
        status: "failed",
        error: {
          kind: "unavailable",
          status: 0,
          message: error instanceof Error ? error.message : "Boot failed",
        },
      };
    }
  }

  return { state, load };
}
