defmodule CadenceWeb.Console.SpacecraftWorkspaceWordsTest do
  @moduledoc "ux's U94 words for the workspace's refusals (api-ops' review nits a-d)."
  use ExUnit.Case, async: true

  alias CadenceWeb.Console.SpacecraftWorkspaceWords, as: Words

  test "catalog revisions read in number order, once each" do
    assert Words.catalog_label([5, 4]) == "catalog revs 4 and 5"
    assert Words.catalog_label([14, nil, 14]) == "catalog rev 14"
    assert Words.catalog_label([9, 3, 6]) == "catalog revs 3, 6 and 9"
    assert Words.catalog_label([nil]) == nil
  end

  test "the model gate's refusal agrees in number" do
    one =
      Words.message(:mission_model_revision_not_approved, :submit, %{catalog: "catalog rev 14"})

    assert one =~ "Not sent: catalog rev 14 isn't approved yet."

    many =
      Words.message(:mission_model_revision_not_approved, :submit, %{
        catalog: Words.catalog_label([5, 4])
      })

    assert many ==
             "Not sent: catalog revs 4 and 5 aren't approved yet. An org admin approves them in Setup › Catalog first."

    assert one =~ "An org admin approves it in Setup › Catalog first."

    assert Words.message(:mission_model_revision_not_approved, :submit, %{}) =~
             "Not sent: the catalog revision isn't approved yet."
  end

  test "a refusal a save and a submit share opens by action; never an id" do
    ctx = %{name: "EARENDIL-004"}

    assert Words.message(:spacecraft_catalog_set_by_profile, :save, ctx) =~
             "Not saved: EARENDIL-004's profile sets its catalog revision."

    assert Words.message(:spacecraft_catalog_set_by_profile, :submit, ctx) =~
             "Not sent: EARENDIL-004's profile sets its catalog revision."

    assert Words.message(:spacecraft_catalog_unavailable, :submit, ctx) =~
             "Not sent: that catalog revision isn't one of this mission's catalog revisions."

    assert Words.message(:spacecraft_not_found, :show, %{name: nil}) ==
             "This spacecraft isn't on this mission."
  end
end
