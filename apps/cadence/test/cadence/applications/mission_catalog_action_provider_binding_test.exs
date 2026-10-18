defmodule Cadence.Applications.MissionCatalogActionProviderBindingTest do
  use ExUnit.Case, async: true

  alias Cadence.Applications.{ActionRequest, HostContext, MissionCatalog}
  alias Cadence.Applications.MissionCatalog.ActionProvider
  alias Cadence.Auth.Scope

  @expected [
    {"mission_new", 1, "validate"},
    {"mission_new", 1, "save"},
    {"mission_applications", 1, "install"},
    {"mission_applications", 1, "disable"},
    {"mission_applications", 1, "uninstall"},
    {"catalog_database_new", 1, "validate"},
    {"catalog_database_new", 1, "save"},
    {"catalog_database_new", 1, "cancel-upload"},
    {"catalog_database_show", 1, "toggle-revision-form"},
    {"catalog_database_show", 1, "validate"},
    {"catalog_database_show", 1, "save"},
    {"catalog_database_show", 1, "cancel-upload"},
    {"catalog_artifact_show", 1, "reimport"}
  ]

  test "freezes the exact 13-row Mission Catalog surface/action ledger" do
    definition_pairs =
      MissionCatalog.definition().surfaces
      |> Enum.flat_map(fn surface ->
        Enum.map(surface.actions, &{surface.surface_id, surface.version, &1})
      end)

    assert definition_pairs == @expected
    assert ActionProvider.surface_action_bindings() == @expected
    assert :ok = ActionProvider.validate_bindings(@expected)
    assert length(Enum.uniq(@expected)) == 13
  end

  test "rejects omitted, wrong-version, cross-surface, and undeclared bindings" do
    base = %ActionRequest{
      application_key: "mission_catalog",
      application_version: 1,
      action_id: "validate",
      surface_id: "mission_new",
      surface_version: 1,
      params: %{}
    }

    requests = [
      %{base | surface_id: nil, surface_version: nil},
      %{base | surface_version: 2},
      %{base | action_id: "reimport", surface_id: "mission_new"},
      %{base | action_id: "save", surface_id: "catalog_artifact_show"},
      %{base | action_id: "not_declared"}
    ]

    for request <- requests do
      assert {:error, :unsupported_application_action} =
               ActionProvider.execute(
                 %Scope{},
                 HostContext.organization("org-mission-catalog"),
                 request
               )
    end
  end

  test "rejects duplicate binding rows" do
    assert {:error, :duplicate_action_bindings} =
             ActionProvider.validate_bindings(@expected ++ [List.first(@expected)])
  end
end
