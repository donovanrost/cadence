defmodule CadenceWeb.ActivationLifecycleTest do
  @moduledoc """
  L10: a requester withdraws a pending request; reject never waits on the policy; a newer request
  supersedes older pending ones for the same binding set, or for overlapping spacecraft when it
  reviews spacecraft configuration; and a superseded request can't be approved.
  """
  use CadenceWeb.ConnCase, async: false

  import Ecto.Query

  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.Auth.Scope
  alias Cadence.Catalog.ConfigurationReviews
  alias Cadence.Governance.ActivationPolicy
  alias Cadence.Management.Activations
  alias Cadence.OperationalEvents.EventRow
  alias CadenceWeb.TestFixtures

  setup do
    user = TestFixtures.persist_user!()
    requester = TestFixtures.persist_user!(display_name: "Flight requester")
    org = TestFixtures.persist_org!()
    membership = TestFixtures.grant_membership!(user, org, role: :organization_admin)
    TestFixtures.grant_membership!(requester, org)
    mission = TestFixtures.persist_mission!(org)

    scope = %Scope{
      actor_kind: :user,
      user: user,
      organization_id: org.organization_id,
      mission_id: mission.mission_id,
      organization_membership: membership,
      capabilities: MapSet.new([:organization_admin])
    }

    %{
      scope: scope,
      requester: %{scope | user: requester},
      org: org.organization_id,
      mission: mission.mission_id,
      binding_set_id: binding_set!(org.organization_id, mission.mission_id)
    }
  end

  test "the requester withdraws a pending request; nobody else can", c do
    {:ok, pending} = request(c, c.binding_set_id)

    assert {:error, :not_requester} =
             Activations.withdraw(c.scope, pending.activation_request_id, "Not mine")

    assert {:error, :invalid_reason} =
             Activations.withdraw(c.requester, pending.activation_request_id, " ")

    assert {:ok, %{state: :withdrawn}, %{decision: :withdrawn, reason: "Wrong basis"}} =
             Activations.withdraw(c.requester, pending.activation_request_id, " Wrong basis ")

    assert {:error, :activation_request_not_pending_approval} =
             Activations.approve(c.scope, pending.activation_request_id, "Too late")
  end

  test "reject goes through after the policy changed; approve doesn't", c do
    {:ok, first} = request(c, c.binding_set_id)
    {:ok, second} = request(c, binding_set!(c.org, c.mission))

    policy = ActivationPolicy.load(c.org, c.mission)

    {:ok, _} =
      ActivationPolicy.save(c.scope, c.mission, policy.token, %{
        "value" => %{"approval_requirement" => "direct"}
      })

    assert {:error, :activation_policy_changed} =
             Activations.approve(c.scope, first.activation_request_id, "Looks right")

    assert {:ok, %{state: :rejected}, _decision} =
             Activations.reject(
               c.scope,
               second.activation_request_id,
               "Stuck under the old policy"
             )
  end

  test "a newer request for the same binding set supersedes the older one, which can't be approved",
       c do
    {:ok, old} = request(c, c.binding_set_id)
    {:ok, other} = request(c, binding_set!(c.org, c.mission))
    {:ok, new} = request(c, c.binding_set_id)

    assert {:ok, %{state: :superseded, superseded_by: by, superseded_at: %DateTime{}}} =
             Activations.fetch(c.scope, old.activation_request_id)

    assert by == new.activation_request_id

    assert {:ok, %{state: :approval_pending}} =
             Activations.fetch(c.scope, other.activation_request_id)

    assert {:error, :activation_request_not_pending_approval} =
             Activations.approve(c.scope, old.activation_request_id, "Stale")

    assert [_event] =
             Cadence.Repo.all(
               from(e in EventRow,
                 where: e.kind == "activation_superseded" and e.mission_id == ^c.mission
               )
             )
  end

  test "a configuration request supersedes only older ones reviewing overlapping spacecraft", c do
    {:ok, a} = request(c, c.binding_set_id, reviews(c, ["sc-a"]))
    {:ok, b} = request(c, c.binding_set_id, reviews(c, ["sc-b"]))
    {:ok, ab} = request(c, c.binding_set_id, reviews(c, ["sc-a", "sc-c"]))

    assert {:ok, %{state: :superseded, superseded_by: by}} =
             Activations.fetch(c.scope, a.activation_request_id)

    assert by == ab.activation_request_id

    assert {:ok, %{state: :approval_pending}} =
             Activations.fetch(c.scope, b.activation_request_id)
  end

  # Review evidence is stored by hash; the metadata carries only its reference (#734).
  defp reviews(c, ids) do
    {:ok, stored} =
      ConfigurationReviews.store(
        c.mission,
        Enum.map(
          ids,
          &%{id: &1, configuration_revision_id: "r-#{&1}", configuration_token: "t-#{&1}"}
        )
      )

    %{
      "spacecraft_configuration_version" => 2,
      "configuration_review" => ConfigurationReviews.metadata(stored, nil)
    }
  end

  defp request(c, binding_set_id, metadata \\ %{}),
    do: Activations.request(c.requester, c.mission, binding_set_id, 1, metadata: metadata)

  defp binding_set!(org, mission) do
    binding =
      BindingSet.new(%{
        organization_id: org,
        mission_id: mission,
        binding_set_id: Cadence.Ids.new("review-basis"),
        version: 1
      })

    {:ok, binding} = Cadence.Governance.persist_binding_set(org, binding)
    binding.binding_set_id
  end
end
