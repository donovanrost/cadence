defmodule Cadence.Applications.SpacecraftConfiguration.DraftsMaySaveTest do
  @moduledoc """
  Lead on #620: the workspace snapshot's `can_save` and `Drafts.save` share one check,
  `Drafts.may_save?/2`, which `authorize/3` runs, so the two can't drift.
  """
  use Cadence.DataCase, async: false

  alias Cadence.Applications.SpacecraftConfiguration.Drafts
  alias Cadence.Auth.Scope
  alias Cadence.CommandReviewFixtures

  test "a member who may operate the mission may save; another mission's scope or no person may not" do
    c = CommandReviewFixtures.scope!()

    assert Drafts.may_save?(c.scope, c.mission)
    refute Drafts.may_save?(%{c.scope | mission_id: "another-mission"}, c.mission)
    refute Drafts.may_save?(%Scope{organization_id: c.org}, c.mission)

    # authorize/3 refuses the same scopes, with the same code as before.
    assert {:error, :invalid_spacecraft_scope} =
             Drafts.authorize(%{c.scope | mission_id: "another-mission"}, c.mission, "craft")
  end
end
