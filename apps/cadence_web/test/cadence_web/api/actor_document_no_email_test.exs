defmodule CadenceWeb.API.ActorDocumentNoEmailTest do
  @moduledoc """
  #466 (#462). The REST actor document is stored as kind, id and display name only, with no
  `user_email`. The REST commanding and activation encoders never send an email that a row
  written before #466 still holds (#116 leaves those rows as they are). The strip runs only at
  the encoder; the domain structs, and any hash computed from them, see the stored document
  unchanged.
  """
  use ExUnit.Case, async: true

  alias Cadence.Accounts.User
  alias Cadence.Auth.Scope

  alias Cadence.Control.Activations.ActivationExecution
  alias Cadence.Management.Activations.{ActivationDecision, ActivationRequest}
  alias CadenceWeb.ActivationJSON
  alias CadenceWeb.ControlPlaneAccess

  # A person's actor document as REST commanding stored it before #466.
  @old_rest %{
    "actor_kind" => "user",
    "organization_id" => "org-466",
    "mission_id" => "mission-466",
    "user_id" => "user-466",
    "user_email" => "person@example.test",
    "user_display_name" => "Mira K."
  }

  # A person's actor document as Management.Activations stored it before #466.
  @old_activation %{
    "kind" => "user",
    "id" => "user-466",
    "display_name" => "Mira K.",
    "email" => "person@example.test"
  }

  describe "ControlPlaneAccess.actor_document/1 (the stored REST actor)" do
    test "a person's document has no email key" do
      user =
        User.new(%{user_id: "user-466", email: "person@example.test", display_name: "Mira K."})

      scope =
        Scope.new(%{user: user, organization_id: "org-466", mission_id: "mission-466"})

      assert ControlPlaneAccess.actor_document(scope) == %{
               "actor_kind" => "user",
               "organization_id" => "org-466",
               "mission_id" => scope.mission_id,
               "user_id" => "user-466",
               "user_display_name" => "Mira K."
             }
    end
  end

  # REST commanding's actors are {kind, id, name} since #465, named against the organization
  # (CadenceWeb.API.RESTCommandingActorsTest covers them, the old-form rows included).

  describe "REST activation JSON reads an old-form row without its email" do
    test "an activation request's requester" do
      json =
        ActivationJSON.request(
          struct(ActivationRequest,
            requester_actor_document: @old_activation,
            change_class: :mission_data_plane,
            state: :pending
          )
        )

      assert json.requester_actor == Map.delete(@old_activation, "email")
    end

    test "an activation decision's actor" do
      json =
        ActivationJSON.decision(
          struct(ActivationDecision, actor_document: @old_activation, decision: :approved)
        )

      assert json.actor == Map.delete(@old_activation, "email")
    end

    test "an activation execution's executor" do
      json =
        ActivationJSON.execution(
          struct(ActivationExecution,
            executor_actor_document: @old_activation,
            status: :succeeded
          )
        )

      assert json.executor_actor == Map.delete(@old_activation, "email")
    end
  end
end
