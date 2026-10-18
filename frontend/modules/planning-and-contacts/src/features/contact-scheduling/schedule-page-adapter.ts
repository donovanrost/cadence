import type { OpsPagePort, OpsPageReadPort } from "@cadence/plugin-sdk/ops-pages";
import { record } from "@cadence/plugin-sdk/admission";
import type { ContactPage } from "./contact-workflow";
import { createContactScheduleService } from "./schedule-service";

export function createPageScheduleService(
  page: Extract<ContactPage, { kind: "schedule" }>,
  port: OpsPagePort,
  readPort: OpsPageReadPort,
  active: () => boolean,
) {
  function admitted() {
    if (!active()) throw Error("The scheduling view has departed.");
  }
  return createContactScheduleService(
    {
      async read() {
        admitted();
        const value = await readPort.read();
        admitted();
        if (!record(value) || value.kind !== "schedule" || value.actor_id !== page.actor_id)
          throw Error("Different scheduling page");
        return value.model;
      },
      async execute(action, input) {
        admitted();
        const value = await port.execute(action, input);
        admitted();
        return value;
      },
    },
    page.model.context,
    page.actor_id,
  );
}
