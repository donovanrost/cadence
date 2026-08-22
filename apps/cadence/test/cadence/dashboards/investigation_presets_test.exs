defmodule Cadence.Dashboards.InvestigationPresetsTest do
  use Cadence.DataCase, async: false

  alias Cadence.Dashboards
  alias Cadence.Dashboards.{Document, InvestigationPreset}

  test "saves, lists, fetches, and deletes dashboard investigation presets" do
    organization_id = unique_id("org-preset")
    mission_id = unique_id("mission-preset")
    dashboard_id = unique_id("dashboard-preset")

    persist_dashboard!(organization_id, mission_id, dashboard_id)

    assert {:ok, %InvestigationPreset{} = preset} =
             Dashboards.save_dashboard_investigation_preset(
               organization_id,
               mission_id,
               dashboard_id,
               %{
                 name: "Late data comparison",
                 description: "Compare canonical against all revisions",
                 payload: comparison_payload(),
                 created_by: "operator-1"
               },
               actor_id: "operator-2"
             )

    assert preset.organization_id == organization_id
    assert preset.mission_id == mission_id
    assert preset.dashboard_id == dashboard_id
    assert preset.name == "Late data comparison"
    assert preset.schema == "dashboard_comparison_investigation_preset.v1"
    assert preset.preset_kind == :comparison

    assert preset.runtime_query == %{
             "compare_data_view" => "canonical",
             "data_view" => "all_revisions"
           }

    assert preset.primary_data_view == "all_revisions"
    assert preset.compare_data_view == "canonical"
    assert preset.affected_placement_ids == ["placement-1", "placement-2"]
    assert preset.created_by == "operator-2"
    assert preset.updated_by == "operator-2"

    assert [listed] =
             Dashboards.list_dashboard_investigation_presets(
               organization_id,
               mission_id,
               dashboard_id
             )

    assert listed.dashboard_investigation_preset_id == preset.dashboard_investigation_preset_id

    assert {:ok, fetched} =
             Dashboards.fetch_dashboard_investigation_preset(
               organization_id,
               mission_id,
               dashboard_id,
               preset.dashboard_investigation_preset_id
             )

    assert fetched.payload["comparison"]["delta_count"] == 1

    assert :ok =
             Dashboards.delete_dashboard_investigation_preset(
               organization_id,
               mission_id,
               dashboard_id,
               preset.dashboard_investigation_preset_id
             )

    assert [] =
             Dashboards.list_dashboard_investigation_presets(
               organization_id,
               mission_id,
               dashboard_id
             )
  end

  test "requires unique preset names within one dashboard" do
    organization_id = unique_id("org-preset-unique")
    mission_id = unique_id("mission-preset-unique")
    dashboard_id = unique_id("dashboard-preset-unique")

    persist_dashboard!(organization_id, mission_id, dashboard_id)

    attrs = %{name: "Rehearsal discrepancy", payload: comparison_payload()}

    assert {:ok, %InvestigationPreset{}} =
             Dashboards.save_dashboard_investigation_preset(
               organization_id,
               mission_id,
               dashboard_id,
               attrs
             )

    assert {:error, changeset} =
             Dashboards.save_dashboard_investigation_preset(
               organization_id,
               mission_id,
               dashboard_id,
               attrs
             )

    assert {:name, {"has already been taken", _metadata}} =
             Enum.find(changeset.errors, fn {field, _error} -> field == :name end)
  end

  test "rejects saving presets for missing or archived dashboards" do
    organization_id = unique_id("org-preset-archived")
    mission_id = unique_id("mission-preset-archived")
    dashboard_id = unique_id("dashboard-preset-archived")

    persist_dashboard!(organization_id, mission_id, dashboard_id)

    assert :ok =
             Dashboards.archive_document(
               organization_id,
               mission_id,
               dashboard_id
             )

    assert {:error, :dashboard_archived} =
             Dashboards.save_dashboard_investigation_preset(
               organization_id,
               mission_id,
               dashboard_id,
               %{name: "Archived compare", payload: comparison_payload()}
             )

    assert {:error, :dashboard_not_found} =
             Dashboards.save_dashboard_investigation_preset(
               organization_id,
               mission_id,
               "missing-dashboard",
               %{name: "Missing compare", payload: comparison_payload()}
             )
  end

  defp persist_dashboard!(organization_id, mission_id, dashboard_id) do
    persist_mission_scope(organization_id, mission_id)

    document = %Document{
      dashboard_id: dashboard_id,
      organization_id: organization_id,
      mission_id: mission_id,
      name: dashboard_id,
      description: "Dashboard investigation preset test"
    }

    assert {:ok, %Document{}} = Dashboards.persist_document(organization_id, document)
  end

  defp unique_id(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"

  defp comparison_payload do
    %{
      "schema" => "dashboard_comparison_investigation_preset.v1",
      "runtime_query" => %{
        "data_view" => "all_revisions",
        "compare_data_view" => "canonical"
      },
      "comparison" => %{
        "primary_data_view" => "all_revisions",
        "compare_data_view" => "canonical",
        "delta_count" => 1
      },
      "groups" => [
        %{
          "key" => "deltas",
          "placement_ids" => ["placement-1"],
          "items" => [%{"placement_id" => "placement-1", "state" => "increased"}]
        },
        %{
          "key" => "missing",
          "placement_ids" => ["placement-2"],
          "items" => [%{"placement_id" => "placement-2", "state" => "missing"}]
        }
      ]
    }
  end
end
