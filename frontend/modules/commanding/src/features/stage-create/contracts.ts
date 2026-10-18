import type { OpsPageContext } from "@cadence/plugin-sdk/ops-pages";
import {
  bounded,
  digest,
  fail,
  id,
  identity,
  text,
  visibility,
  type Identity,
} from "../../shared/stages/validation";
import { readOperation, type Operation } from "../../shared/stages/operations";
export type Creation = Identity & { stage_id: string };
export type CreationPage = {
  creation: Creation;
  write_token: string | null;
  operation: Operation | null;
};
export function readCreationPage(value: unknown, context: OpsPageContext): CreationPage {
  bounded(value, 12000);
  const c = value.creation;
  identity(c, context);
  if (!id(c.stage_id) || !(value.write_token === null || digest(value.write_token))) return fail();
  const operation =
    value.operation === null ? null : readOperation(value.operation, c.actor_id, c.stage_id);
  if (operation && (operation.event !== "create" || value.write_token !== null)) return fail();
  if (!operation && value.write_token === null) return fail();
  return { creation: c as Creation, write_token: value.write_token as string | null, operation };
}
export function createInput(token: string, name: string, description: string, access: string) {
  if (
    !digest(token) ||
    !text(name, 240) ||
    !name.trim() ||
    !text(description, 4000) ||
    !visibility(access)
  )
    throw Error("Enter a name up to 240 UTF-8 bytes and a description up to 4,000 bytes.");
  return { expected_write: token, name, description: description || null, visibility: access };
}
