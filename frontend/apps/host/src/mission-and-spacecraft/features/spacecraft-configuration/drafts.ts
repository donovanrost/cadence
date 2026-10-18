import { reactive } from "vue";
import type { ConfigurationDocument, ConfigurationSnapshot } from "./contracts";

export const equalDocuments = (left: ConfigurationDocument, right: ConfigurationDocument) =>
  JSON.stringify(left) === JSON.stringify(right);
export type DraftSession = {
  snapshot: ConfigurationSnapshot;
  baseline: ConfigurationDocument;
  draft: ConfigurationDocument;
  token: string;
  conflict: boolean;
  busy: boolean;
  feedback: string | null;
};
export function createConfigurationDrafts() {
  const sessions = new Map<string, DraftSession>();
  function receive(snapshot: ConfigurationSnapshot): DraftSession {
    const key = `${snapshot.organization_id}/${snapshot.mission_id}/${snapshot.spacecraft_id}`;
    let session = sessions.get(key);
    if (!session) {
      if (sessions.size >= 100) {
        const removable = [...sessions].find(
          ([, item]) => !item.busy && equalDocuments(item.draft, item.baseline),
        );
        if (!removable)
          throw new Error("Save a spacecraft draft before opening another configuration.");
        sessions.delete(removable[0]);
      }
      session = reactive({
        snapshot,
        baseline: snapshot.document,
        draft: snapshot.document,
        token: snapshot.token,
        conflict: false,
        busy: false,
        feedback: null,
      });
      sessions.set(key, session);
      return session;
    }
    const dirty = !equalDocuments(session.draft, session.baseline);
    if (!dirty || equalDocuments(snapshot.document, session.draft)) {
      session.baseline = snapshot.document;
      session.draft = snapshot.document;
      session.token = snapshot.token;
      session.conflict = false;
    } else if (equalDocuments(snapshot.document, session.baseline)) {
      session.token = snapshot.token;
    } else {
      session.conflict = true;
    }
    session.snapshot = snapshot;
    return session;
  }
  return {
    receive,
    acceptSaved(snapshot: ConfigurationSnapshot) {
      const session = receive(snapshot);
      session.baseline = snapshot.document;
      session.draft = snapshot.document;
      session.token = snapshot.token;
      session.conflict = false;
    },
    clear: () => sessions.clear(),
    hasUnsaved: () =>
      [...sessions.values()].some((session) => !equalDocuments(session.draft, session.baseline)),
    changed: (id: string) =>
      [...sessions.values()].some(
        (session) =>
          session.snapshot.spacecraft_id === id && !equalDocuments(session.draft, session.baseline),
      ),
  };
}
export type ConfigurationDrafts = ReturnType<typeof createConfigurationDrafts>;
