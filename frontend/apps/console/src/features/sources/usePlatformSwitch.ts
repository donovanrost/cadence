import { computed } from "vue";
import { hasCapability, useAdminMode, useSession } from "@/shell";

/** U53: only a platform admin in admin mode switches a platform-wide binding (the server's rule). */
export function usePlatformSwitch() {
  const session = useSession();
  const adminMode = useAdminMode(() => new Date()).active;
  return computed(() => adminMode.value && hasCapability(session, "platform_admin"));
}
