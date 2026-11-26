defmodule Cadence.Management.ActivationActorDocumentsTest do
  @moduledoc """
  #466 (#462): an activation request's requester and an activation decision's actor are stored
  as kind, id and display name only. No email key is written, so no later read can leak it.
  """
  use Cadence.DataCase, async: false

  alias Cadence.Accounts.User
  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.Auth.Scope
  alias Cadence.Management.Activations
  alias Cadence.Management.Activations.{ActivationDecisionRow, ActivationRequestRow}
  alias Cadence.Persistence.JsonDocument

  setup do
    organization_id = "org-466-activations"
    mission_id = "mission-466-activations"
    persist_mission_scope(organization_id, mission_id)

    binding_set =
      BindingSet.new(%{
        organization_id: organization_id,
        mission_id: mission_id,
        binding_set_id: "basis-466",
        version: 1
      })

    {:ok, _} = Cadence.Governance.persist_binding_set(organization_id, binding_set)

    %{organization_id: organization_id, mission_id: mission_id}
  end

  test "the stored requester and decision documents carry no email", c do
    requester = person(c.organization_id, "requester-466")
    decider = person(c.organization_id, "decider-466")

    assert {:ok, request} = Activations.request(requester, c.mission_id, "basis-466", 1)

    assert {:ok, _request, _decision} =
             Activations.reject(decider, request.activation_request_id, "no")

    request_row =
      Repo.get_by!(ActivationRequestRow, activation_request_id: request.activation_request_id)

    decision_row =
      Repo.get_by!(ActivationDecisionRow, activation_request_id: request.activation_request_id)

    assert stored(request_row.requester_actor_document) == %{
             "kind" => "user",
             "id" => "requester-466",
             "display_name" => "Requester 466"
           }

    assert stored(decision_row.actor_document) == %{
             "kind" => "user",
             "id" => "decider-466",
             "display_name" => "Decider 466"
           }
  end

  defp stored(document), do: JsonDocument.unwrap_value(document)

  defp person(organization_id, user_id) do
    user =
      User.new(%{
        user_id: user_id,
        email: user_id <> "@example.test",
        display_name: user_id |> String.replace("-", " ") |> String.capitalize(),
        capabilities: [:platform_admin]
      })

    Scope.new(%{user: user, organization_id: organization_id, admin_mode?: true})
  end
end
