defmodule CadenceWeb.API.ActorDocumentNoEmailTest do
  @moduledoc """
  #466 (#462). The REST actor document is stored as kind, id and display name only, with no
  `user_email`. (The REST activation encoder this also covered went with #748.)
  """
  use ExUnit.Case, async: true

  alias Cadence.Accounts.User
  alias Cadence.Auth.Scope
  alias CadenceWeb.ControlPlaneAccess

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
end
