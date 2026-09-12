import type { Component } from "vue";
import type { OpsPageContribution } from "@cadence/plugin-sdk/ops-pages";
import ContactScheduleContribution from "./ContactScheduleContribution.vue";
import ContactRecordContribution from "./ContactRecordContribution.vue";
import ReservationContribution from "./ReservationContribution.vue";
import {
  admitContactPage,
  scheduleActions,
  reservationActions,
  type ContactKind,
} from "./contact-workflow";
function contribution(
  kind: ContactKind,
  id: string,
  title: string,
  component: Component,
): OpsPageContribution<Component> {
  return {
    id,
    slot: "ops.page",
    version: 1,
    title,
    component,
    query: true,
    actions:
      kind === "schedule" ? scheduleActions : kind === "reservation" ? reservationActions : [],
    read(value, context) {
      if (kind !== "schedule" && !context.resourceId) throw Error("Missing contact identity");
      const page = admitContactPage(kind, value, {
        organization_id: context.organizationId,
        mission_id: context.missionId,
        ...(context.resourceId === undefined ? {} : { resource_id: context.resourceId }),
      });
      if (!page) throw Error("Unavailable contact evidence");
      return { page };
    },
  };
}
export const contactScheduleContribution = contribution(
  "schedule",
  "planning.contact-schedule",
  "Contact Schedule",
  // oxlint-disable-next-line typescript/no-unsafe-argument -- vue-tsc checks this SFC constructor.
  ContactScheduleContribution,
);
export const contactRecordContribution = contribution(
  "record",
  "planning.contact-record",
  "Contact Record",
  // oxlint-disable-next-line typescript/no-unsafe-argument -- vue-tsc checks this SFC constructor.
  ContactRecordContribution,
);
export const reservationContribution = contribution(
  "reservation",
  "planning.reservation-review",
  "Reservation Review",
  // oxlint-disable-next-line typescript/no-unsafe-argument -- vue-tsc checks this SFC constructor.
  ReservationContribution,
);
