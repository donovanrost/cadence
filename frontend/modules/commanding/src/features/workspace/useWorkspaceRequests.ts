import { onBeforeUnmount, ref } from "vue";
import type { OpsPagePort } from "@cadence/plugin-sdk/ops-pages";

/** Order operations on the server session without disabling the UI. */
export function useWorkspaceRequests(port: OpsPagePort) {
  const pending = ref(0);
  let disposed = false;
  let tail: Promise<void> = Promise.resolve();
  onBeforeUnmount(() => {
    disposed = true;
  });
  function execute(
    event: string,
    input: Record<string, unknown>,
    current = () => true,
  ): Promise<unknown> {
    pending.value++;
    const request = tail.then(() => {
      if (disposed || !current()) return { status: "superseded" };
      return port.execute(event, input);
    });
    tail = request.then(
      () => {},
      () => {},
    );
    return request.finally(() => {
      pending.value--;
    });
  }
  return { execute, pending };
}
