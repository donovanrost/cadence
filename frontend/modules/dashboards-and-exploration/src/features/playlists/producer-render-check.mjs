import assert from "node:assert/strict";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { createServer } from "vite-plus";
import vue from "@vitejs/plugin-vue";
import { Window } from "happy-dom";
import { createSSRApp } from "vue";
import { renderToString } from "vue/server-renderer";
const server = await createServer({
  configFile: false,
  root: resolve(dirname(fileURLToPath(import.meta.url)), "../../.."),
  plugins: [vue()],
  server: { middlewareMode: true, hmr: false },
  // GridStack 10 publishes ESM with extensionless internal imports.
  ssr: { noExternal: ["@cadence/ui", "gridstack"] },
  logLevel: "error",
});
try {
  const { playlistsContribution, playlistPresentationContribution } =
    await server.ssrLoadModule("/src/playlists.ts");
  for (const model of JSON.parse(process.argv[2])) {
    const present = Object.hasOwn(model, "playlist"),
      registration = present ? playlistPresentationContribution : playlistsContribution;
    const context = {
      organizationId: model.organization_id,
      missionId: model.mission_id,
      ...(present ? { resourceId: model.playlist.id } : {}),
    };
    const props = registration.read(
      present ? model : { model, phase: "ready", sequence: 0 },
      context,
    );
    const app = createSSRApp(registration.component, {
      ...props,
      refresh: async () => {},
      port: {
        execute() {
          throw Error("Unexpected effect");
        },
        navigate() {},
      },
    });
    app.config.warnHandler = (message) => {
      throw Error(message);
    };
    const html = await renderToString(app),
      window = new Window();
    try {
      window.document.body.innerHTML = html;
      const doc = window.document;
      assert.ok(
        doc.getElementById(
          present ? "playlist-presentation-feature" : "playlist-directory-feature",
        ),
      );
      if (present) {
        assert.equal(
          !!doc.getElementById("playlist-current-unavailable"),
          model.current.snapshot === null,
        );
        assert.equal(
          doc.getElementById("playlist-current-name").textContent.trim(),
          model.current.name || "Unavailable dashboard",
        );
        assert.ok(
          doc
            .getElementById("playlist-position")
            .textContent.includes(`${model.index + 1} / ${model.total}`),
        );
      } else {
        assert.equal(
          doc.querySelectorAll("#playlist-saved-list>li").length,
          model.playlists.rows.length,
        );
        assert.equal(
          doc.querySelectorAll("#playlist-choices>li").length,
          model.choices.rows.length,
        );
      }
    } finally {
      await window.happyDOM.close();
    }
  }
  console.log("Playlist producer/renderer contracts passed.");
} finally {
  await server.close();
}
