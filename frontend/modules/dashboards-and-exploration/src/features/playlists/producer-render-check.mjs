import {
  fixtureRows,
  fixtureString,
  fixtureRecord,
} from "../../../../../test-support/json-fixture.ts";
import { required } from "../../../../../test-support/required.ts";
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
    /** @type {typeof import("../../playlists.ts")} */ (
      await server.ssrLoadModule("/src/playlists.ts")
    );
  for (const raw of fixtureRows(process.argv[2])) {
    const present = Object.hasOwn(raw, "playlist"),
      registration = present ? playlistPresentationContribution : playlistsContribution;
    const context = {
      organizationId: fixtureString(raw.organization_id),
      missionId: fixtureString(raw.mission_id),
      ...(present ? { resourceId: fixtureString(fixtureRecord(raw.playlist).id) } : {}),
    };
    const props = present
      ? playlistPresentationContribution.read(raw, context)
      : playlistsContribution.read({ model: raw, phase: "ready", sequence: 0 }, context);
    // oxlint-disable-next-line typescript/no-unsafe-argument -- vue-tsc checks the SFC constructor at this registration or render boundary.
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
      if ("model" in props) {
        const model = props.model;
        assert.equal(
          !!doc.getElementById("playlist-current-unavailable"),
          model.current.snapshot === null,
        );
        assert.equal(
          required(doc.getElementById("playlist-current-name")).textContent.trim(),
          model.current.name || "Unavailable dashboard",
        );
        assert.ok(
          required(doc.getElementById("playlist-position")).textContent.includes(
            `${model.index + 1} / ${model.total}`,
          ),
        );
      } else {
        const model = props.state.model;
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
