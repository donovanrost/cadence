export { default as OpsContactSchedule } from "./features/contact-scheduling/OpsContactSchedule.vue";
export type {
  OpsContactScheduleProps,
  ContactSchedulePort,
  ContactSchedule,
  ScheduleAction,
  ScheduleInputs,
  ScheduleRequest,
} from "./features/contact-scheduling/OpsContactSchedule.contracts";
export { default as OpsContactDetail } from "./features/contact-scheduling/OpsContactDetail.vue";
export type {
  OpsContactDetailProps,
  ReservationDetail,
  ReservationAction,
  ReservationDecision,
  ReservationRequest,
  ReservationPort,
} from "./features/contact-scheduling/OpsContactDetail.contracts";
export { default as OpsContactRecord } from "./features/contact-scheduling/OpsContactRecord.vue";
export type {
  OpsContactRecordProps,
  ContactRecord,
  ContactRecordPort,
} from "./features/contact-scheduling/OpsContactRecord.contracts";
export { RESERVATION_PORT } from "./features/contact-scheduling/OpsContactDetail.contracts";
export { CONTACT_RECORD_PORT } from "./features/contact-scheduling/OpsContactRecord.contracts";

export { CONTACT_SCHEDULE_PORT } from "./features/contact-scheduling/OpsContactSchedule.contracts";

export {
  contactScheduleContribution,
  contactRecordContribution,
  reservationContribution,
} from "./features/contact-scheduling/contact.contributions";

export { createContactScheduleService } from "./features/contact-scheduling/schedule-service";
export { admitContactRecord } from "./features/contact-scheduling/contact-record";
export { contactNavigationKey } from "./features/contact-scheduling/contact-navigation";
export type {
  ContactScheduleService,
  ScheduleCommand,
  ScheduleOperation,
  ScheduleProjection,
  ScheduleWireRequest,
} from "./features/contact-scheduling/schedule-service";
