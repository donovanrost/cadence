import type { Ref } from "vue";
import { useOpsHeader } from "@cadence/plugin-sdk/page-header";
import { href } from "@cadence/plugin-sdk/routes";

const directory = "/missions/:mission_id/ops/dashboards";

/** The directory's header: library and playlists, and New for authors. */
export function useDirectoryHeader(mission: Ref<string>, author: () => boolean) {
  useOpsHeader(directory, () => {
    const params = { mission_id: mission.value };
    return {
      description:
        "Telemetry workspaces shared across the mission. Stars and recently viewed are yours alone.",
      actions: [
        {
          id: "library",
          label: "Library",
          icon: "hero-rectangle-stack",
          href: href("/missions/:mission_id/ops/dashboards/library", params),
        },
        {
          id: "playlists",
          label: "Playlists",
          icon: "hero-play",
          href: href("/missions/:mission_id/ops/dashboards/playlists", params),
        },
      ],
      ...(author()
        ? {
            primary: {
              id: "new",
              label: "New",
              icon: "hero-plus",
              menu: [
                {
                  id: "new-dashboard",
                  label: "New dashboard",
                  icon: "hero-squares-plus",
                  href: href("/missions/:mission_id/ops/dashboards/new", params),
                },
                {
                  id: "import",
                  label: "Import",
                  icon: "hero-arrow-down-tray",
                  href: href("/missions/:mission_id/ops/dashboards/new", params, {
                    mode: "import",
                  }),
                },
              ],
            },
          }
        : {}),
    };
  });
}
