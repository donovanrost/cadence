import { test as setup } from "@playwright/test";
import { BASE_URL, PERSONAS, storageStateFor } from "./support/env.ts";
import { signInByApi } from "./support/sign-in.ts";

// One saved session per persona. Specs pick theirs with
// test.use({ storageState: storageStateFor("operator") }); the default is admin.
// Through the sign-in API, never a page: no password is typed where a trace could record it (#242).
for (const persona of Object.values(PERSONAS)) {
  setup(`sign in as ${persona.key}`, async () => {
    await signInByApi(BASE_URL, persona, storageStateFor(persona.key));
  });
}
