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

  alias Cadence.Commanding.{
    CommandApproval,
    CommandQueueEntry,
    CommandReleaseAttempt,
    CommandRequest,
    CommandStage
  }

  alias Cadence.Control.Activations.ActivationExecution
  alias Cadence.Management.Activations.{ActivationDecision, ActivationRequest}
  alias CadenceWeb.ActivationJSON
  alias CadenceWeb.API.CommandingJSON
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

  describe "REST commanding JSON reads an old-form row without its email" do
    test "requested_by" do
      json = CommandingJSON.command_request(struct(CommandRequest, requested_by: @old_rest))
      assert json.requested_by == Map.delete(@old_rest, "user_email")
    end

    test "decided_by" do
      json = CommandingJSON.command_approval(struct(CommandApproval, decided_by: @old_rest))
      assert json.decided_by == Map.delete(@old_rest, "user_email")
    end

    test "enqueued_by" do
      json = CommandingJSON.command_queue_entry(struct(CommandQueueEntry, enqueued_by: @old_rest))
      assert json.enqueued_by == Map.delete(@old_rest, "user_email")
    end

    test "released_by" do
      json =
        CommandingJSON.command_release_attempt(
          struct(CommandReleaseAttempt, released_by: @old_rest)
        )

      assert json.released_by == Map.delete(@old_rest, "user_email")
    end

    test "a stage's owner" do
      json =
        CommandingJSON.command_stage(
          struct(CommandStage, owner: @old_rest, visibility: :private, lifecycle_state: :draft)
        )

      assert json.owner == Map.delete(@old_rest, "user_email")
    end
  end

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
