import { test as setup } from "@playwright/test";
import { PERSONAS, storageStateFor } from "./support/env.ts";
import { signIn } from "./support/sign-in.ts";

// One saved session per persona. Specs pick theirs with
// test.use({ storageState: storageStateFor("operator") }); the default is admin.
for (const persona of Object.values(PERSONAS)) {
  setup(`sign in as ${persona.key}`, async ({ browser }) => {
    const context = await browser.newContext();
    const page = await context.newPage();
    await signIn(page, persona);
    await context.storageState({ path: storageStateFor(persona.key) });
    await context.close();
  });
}
