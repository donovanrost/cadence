import { expect, test } from "vite-plus/test";
import { required } from "../../../../../test-support/required";
import type { ContactSchedulePort, ScheduleRequest } from "./OpsContactSchedule.contracts";
import {
  admitContactOperation,
  contactPageRequest,
  type ContactOperation,
  type ContactPage,
} from "./contact-workflow";
import { contactOperation, contactPage } from "./contact-workflow.test-support";
import { searchFixture } from "./contact-schedule.test-support";

function rejectedPrograms(
  remote: Extract<ContactSchedulePort, { protocol: "remote-query" }>,
  pagePort: Extract<ContactSchedulePort, { protocol: "page-snapshot" }>,
  operation: ContactOperation,
  page: ContactPage,
) {
  // @ts-expect-error A cancellation needs reviewed reservation evidence.
  const wrongInput: ScheduleRequest = ["cancel", { token: "opaque" }];
  void wrongInput;
  // @ts-expect-error The remote protocol takes bare domain inputs.
  void remote.execute("reserve", { sequence: 1, payload: { token: "opaque" } });
  // @ts-expect-error The page protocol needs a recovery sequence.
  void pagePort.execute("reserve", { token: "opaque" });
  // @ts-expect-error A completed booking cannot omit its receipt.
  const missingReceipt: ContactOperation = {
    sequence: 1,
    action: "reserve",
    input: { token: "opaque" },
    status: "completed",
    receipt: null,
  };
  void missingReceipt;
  if (operation.status === "completed" && operation.action === "search") {
    void operation.receipt.result.value.opportunities;
    // @ts-expect-error A search receipt is not a booking receipt.
    void operation.receipt.result.value.providerReservationId;
  }
  if (operation.action === "reserve" && operation.status === "unconfirmed" && operation.receipt) {
    // @ts-expect-error An unconfirmed booking cannot promise an observed completion.
    const observed: "observed" = operation.receipt.result.source;
    void observed;
  }
  if (page.kind === "reservation") {
    // @ts-expect-error The admitted model is an immutable snapshot.
    page.model.reservation.provider_revision = 99;
    // @ts-expect-error The page kind determines its model.
    void page.model.routes;
  }
}
void rejectedPrograms;

test("recorded unconfirmed bookings preserve their receipt and reject an observed source", () => {
  const page = contactPage();
  page.search = searchFixture();
  const request: ScheduleRequest = [
    "reserve",
    { token: required(page.search.opportunities[0]).token },
  ];
  const [action, envelope] = contactPageRequest(request, 1);
  expect(envelope).toEqual({ sequence: 1, payload: request[1] });
  const completed = contactOperation(page, action, envelope);
  for (const lifecycleState of [
    "requesting",
    "canceling",
    "unknown",
    "failed",
    "rejected",
  ] as const) {
    const receipt = {
      ...completed.receipt,
      result: {
        ...completed.receipt.result,
        source: "recorded",
        value: {
          providerReservationId: "reservation-one",
          providerRevision: 1,
          lifecycleState,
          scheduledContactId: null,
        },
      },
    };
    const operation = { ...completed, status: "unconfirmed", receipt };
    expect(admitContactOperation(operation, page)).toEqual(operation);
    expect(
      admitContactOperation(
        {
          ...operation,
          receipt: { ...receipt, result: { ...receipt.result, source: "observed" } },
        },
        page,
      ),
    ).toBeNull();
  }
  expect(
    admitContactOperation({ ...completed, toJSON: () => ({ ...completed, receipt: null }) }, page),
  ).toBeNull();
});
