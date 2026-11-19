defmodule Cadence.Auth.ServiceAccountabilityTest do
  # #280: a service identity's acts count as its accountable people's (issuer, rotators, and
  # whoever an org admin records, that admin included), transitively; unknown fails closed.
  use Cadence.DataCase, async: false

  alias Cadence.Accounts.User
  alias Cadence.Auth
  alias Cadence.Auth.{Scope, ServiceAccountability, ServiceIdentity, ServiceIdentityKeys}
  alias Cadence.Auth.ServiceAccountableRow
  alias Cadence.ContactPlanning.FleetPlanningPolicies
  alias Cadence.Governance.Accountability
  alias Cadence.Repo

  @org "org-service-accountability"
  @mission "mission-service-accountability"

  setup do
    %{organization: organization} = persist_mission_scope(@org, @mission)
    %{organization: organization}
  end

  test "issuing records the issuer; rotating adds the rotator" do
    svc = issue!("svc-acct-a", person("ada"))
    assert {:ok, ["ada"]} = ServiceAccountability.people(@org, svc.service_identity_id)

    assert {:ok, _} = ServiceIdentityKeys.rotate(@org, svc.service_identity_id, person("bo"))
    assert {:ok, ["ada", "bo"]} = ServiceAccountability.people(@org, svc.service_identity_id)
  end

  test "a service issued by a service inherits that service's people" do
    parent = issue!("svc-acct-parent", person("ada"))
    child = issue!("svc-acct-child", service_scope(parent))

    assert {:ok, ["ada"]} = ServiceAccountability.people(@org, child.service_identity_id)
  end

  test "an identity with no issuer on record is unknown, and so is anything it issued" do
    legacy = insert_legacy_identity!("svc-acct-legacy")
    child = issue!("svc-acct-legacy-child", service_scope(legacy))

    assert {:error, :unknown} = ServiceAccountability.people(@org, legacy.service_identity_id)
    assert {:error, :unknown} = ServiceAccountability.people(@org, child.service_identity_id)
  end

  test "a loop between services is unknown" do
    a = issue!("svc-acct-loop-a", person("ada"))
    b = issue!("svc-acct-loop-b", service_scope(a))
    assert {:ok, _} = ServiceIdentityKeys.rotate(@org, a.service_identity_id, service_scope(b))

    assert {:error, :unknown} = ServiceAccountability.people(@org, a.service_identity_id)
  end

  test "an org admin records accountable people and joins the set" do
    legacy = insert_legacy_identity!("svc-acct-attributed")

    assert :ok =
             ServiceAccountability.attribute(admin("cy"), @org, legacy.service_identity_id, [
               "dee"
             ])

    assert {:ok, ["cy", "dee"]} = ServiceAccountability.people(@org, legacy.service_identity_id)
  end

  test "only a person who is an org admin can record accountable people; nothing is written" do
    legacy = insert_legacy_identity!("svc-acct-refused")

    assert {:error, :forbidden} =
             ServiceAccountability.attribute(person("ed"), @org, legacy.service_identity_id, [
               "ed"
             ])

    assert {:error, :authenticated_user_required} =
             ServiceAccountability.attribute(
               service_scope(legacy),
               @org,
               legacy.service_identity_id,
               []
             )

    assert Repo.aggregate(ServiceAccountableRow, :count) == 0
  end

  describe "Accountability.separate/4" do
    test "a person approving their own act is self, via nothing" do
      assert {:error, {:self, nil}} =
               Accountability.separate(@org, {:user, "ada"}, [{:user, "ada"}])

      assert :ok = Accountability.separate(@org, {:user, "bo"}, [{:user, "ada"}])
    end

    test "a service's people count as the author, and the refusal names the service" do
      svc = issue!("svc-acct-author", person("ada"))
      author = %{"actor_kind" => "service", "service_identity_id" => svc.service_identity_id}

      assert {:error, {:self, %{id: id, name: "svc-acct-author"}}} =
               Accountability.separate(@org, {:user, "ada"}, [author])

      assert id == svc.service_identity_id
      assert :ok = Accountability.separate(@org, {:user, "bo"}, [author])
    end

    test "their own act wins when both apply" do
      svc = issue!("svc-acct-both", person("ada"))

      assert {:error, {:self, nil}} =
               Accountability.separate(@org, {:user, "ada"}, [
                 {:service, svc.service_identity_id},
                 {:user, "ada"}
               ])
    end

    test "an unknown service fails closed for every approver" do
      legacy = insert_legacy_identity!("svc-acct-unknown")

      assert {:error, {:unknown, %{id: "svc-acct-unknown"}}} =
               Accountability.separate(@org, {:user, "anyone"}, [{:service, "svc-acct-unknown"}])

      assert legacy.service_identity_id == "svc-acct-unknown"
    end

    test "a service approving under a grant counts as its people plus the grant's approver" do
      planner = issue!("svc-acct-planner", person("ada"))

      # The same service authored and approves: its people are on both sides.
      assert {:error, {:self, %{id: _}}} =
               Accountability.separate(
                 @org,
                 {:service, planner.service_identity_id},
                 [{:service, planner.service_identity_id}],
                 "grant-admin"
               )

      # The grant's approver authored it.
      assert {:error, {:self, nil}} =
               Accountability.separate(
                 @org,
                 {:service, planner.service_identity_id},
                 [{:user, "grant-admin"}],
                 "grant-admin"
               )

      assert :ok =
               Accountability.separate(
                 @org,
                 {:service, planner.service_identity_id},
                 [{:user, "someone-else"}],
                 "grant-admin"
               )
    end

    test "the system actor and unrecorded actors count no one, as before" do
      system = %{"actor_kind" => "system", "system_id" => "seed:x", "name" => "Seed"}
      assert :ok = Accountability.separate(@org, {:user, "ada"}, [system, %{}, nil])
    end
  end

  test "a bare id counts as the person and, when a service has that id, as the service too" do
    svc = issue!("svc-acct-bare", person("ada"))

    assert [{:user, "svc-acct-bare"}, {:user, "bo"}, {:service, "svc-acct-bare"}] =
             Accountability.actors_for_ids(@org, [svc.service_identity_id, "bo", nil])
  end

  # #280 guard: fleet planning policies are person-only, so no service can author one (and so none
  # needs its accountable people). Keeps that true if the actor rule ever loosens.
  test "a service, even an organization admin, can't author a fleet planning policy", c do
    {:ok, %{service_identity: identity}} =
      Auth.issue_service_identity(
        ServiceIdentity.new(%{
          organization_id: @org,
          display_name: "Policy bot",
          capabilities: [:organization_admin]
        }),
        person("ada")
      )

    bot =
      Scope.new(%{
        organization_id: @org,
        organization: c.organization,
        service_identity: identity
      })

    assert {:error, :authenticated_user_required} =
             FleetPlanningPolicies.create(bot, @mission, %{})
  end

  defp issue!(id, issued_by) do
    identity =
      ServiceIdentity.new(%{
        service_identity_id: id,
        organization_id: @org,
        mission_id: @mission,
        display_name: id,
        capabilities: [:mission_admin]
      })

    assert {:ok, %{service_identity: issued}} = Auth.issue_service_identity(identity, issued_by)
    issued
  end

  # An identity issued before #280: no accountable row.
  defp insert_legacy_identity!(id) do
    issued = issue!(id, person("legacy-issuer"))
    Repo.delete_all(from(row in ServiceAccountableRow, where: row.service_identity_id == ^id))
    issued
  end

  defp person(id),
    do: %Scope{actor_kind: :user, organization_id: @org, user: %User{user_id: id}}

  defp admin(id),
    do: %Scope{person(id) | capabilities: MapSet.new([:organization_admin])}

  defp service_scope(identity),
    do: %Scope{actor_kind: :service, organization_id: @org, service_identity: identity}
end
