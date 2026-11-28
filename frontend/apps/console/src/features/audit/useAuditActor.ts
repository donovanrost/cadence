import { computed, type Ref } from "vue";
import { useRoute, useRouter } from "vue-router";
import { useRemoteQuery, type OrganizationId } from "@/api";
import { fetchPeople, type Member } from "@/features/people/index.ts";

export type ActorOption = Readonly<{ value: string; label: string }>;

/** A member by their display name, else their email (the People table's rule). */
const nameOf = (m: Member) => m.display_name ?? m.email;

/**
 * The Actor select's options: everyone, then each member by name. A person in the query who isn't
 * a member any more (or a people read we can't see) still gets an option, so the filter stays honest.
 */
export function actorOptions(
  members: readonly Member[],
  current: Readonly<{ id: string; name: string }> | null,
): ActorOption[] {
  const people = [...members]
    .map((m) => ({ value: m.user_id, label: nameOf(m) }))
    .sort((a, b) => a.label.localeCompare(b.label));
  const missing = current && !people.some((p) => p.value === current.id);
  return [
    { value: "", label: "Everyone" },
    ...(missing ? [{ value: current.id, label: current.name }] : []),
    ...people,
  ];
}

/** Audit's actor filter lives in the query (`?actor=<user_id>&who=<name>`), as People links it. */
export function useAuditActor(organizationId: Ref<OrganizationId | null>) {
  const route = useRoute();
  const router = useRouter();
  const people = useRemoteQuery(organizationId, fetchPeople);
  const members = computed(() =>
    people.state.value.status === "ready" ? people.state.value.value.members : [],
  );
  const id = computed(() =>
    typeof route.query["actor"] === "string" && route.query["actor"] !== ""
      ? route.query["actor"]
      : null,
  );
  const name = computed(() =>
    typeof route.query["who"] === "string" ? route.query["who"] : (id.value ?? ""),
  );
  const options = computed(() =>
    actorOptions(members.value, id.value ? { id: id.value, name: name.value } : null),
  );
  function set(value: string) {
    const label = options.value.find((o) => o.value === value)?.label;
    const { actor: _actor, who: _who, ...rest } = route.query;
    void router.replace({
      query: value && label ? { ...rest, actor: value, who: label } : rest,
    });
  }
  return { id, options, set };
}
export type AuditActor = ReturnType<typeof useAuditActor>;
