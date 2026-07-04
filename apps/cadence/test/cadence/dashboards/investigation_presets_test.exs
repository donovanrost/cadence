defmodule Cadence.Dashboards.InvestigationPresetsTest do
  use Cadence.DataCase, async: false

  alias Cadence.Dashboards
  alias Cadence.Dashboards.{Document, InvestigationPreset}

  test "saves, lists, fetches, and deletes dashboard investigation presets" do
    persist_dashboard!("org-preset", "mission-preset", "dashboard-preset")

    assert {:ok, %InvestigationPreset{} = preset} =
             Dashboards.save_dashboard_investigation_preset(
               "org-preset",
               "mission-preset",
               "dashboard-preset",
               %{
                 name: "Late data comparison",
                 description: "Compare canonical against all revisions",
                 payload: comparison_payload(),
                 created_by: "operator-1"
               },
               actor_id: "operator-2"
             )

    assert preset.organization_id == "org-preset"
    assert preset.mission_id == "mission-preset"
    assert preset.dashboard_id == "dashboard-preset"
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
               "org-preset",
               "mission-preset",
               "dashboard-preset"
             )

    assert listed.dashboard_investigation_preset_id == preset.dashboard_investigation_preset_id

    assert {:ok, fetched} =
             Dashboards.fetch_dashboard_investigation_preset(
               "org-preset",
               "mission-preset",
               "dashboard-preset",
               preset.dashboard_investigation_preset_id
             )

    assert fetched.payload["comparison"]["delta_count"] == 1

    assert :ok =
             Dashboards.delete_dashboard_investigation_preset(
               "org-preset",
               "mission-preset",
               "dashboard-preset",
               preset.dashboard_investigation_preset_id
             )

    assert [] =
             Dashboards.list_dashboard_investigation_presets(
               "org-preset",
               "mission-preset",
               "dashboard-preset"
             )
  end

  test "requires unique preset names within one dashboard" do
    persist_dashboard!("org-preset-unique", "mission-preset-unique", "dashboard-preset-unique")

    attrs = %{name: "Rehearsal discrepancy", payload: comparison_payload()}

    assert {:ok, %InvestigationPreset{}} =
             Dashboards.save_dashboard_investigation_preset(
               "org-preset-unique",
               "mission-preset-unique",
               "dashboard-preset-unique",
               attrs
             )

    assert {:error, changeset} =
             Dashboards.save_dashboard_investigation_preset(
               "org-preset-unique",
               "mission-preset-unique",
               "dashboard-preset-unique",
               attrs
             )

    assert {:name, {"has already been taken", _metadata}} =
             Enum.find(changeset.errors, fn {field, _error} -> field == :name end)
  end

  test "rejects saving presets for missing or archived dashboards" do
    persist_dashboard!(
      "org-preset-archived",
      "mission-preset-archived",
      "dashboard-preset-archived"
    )

    assert :ok =
             Dashboards.archive_document(
               "org-preset-archived",
               "mission-preset-archived",
               "dashboard-preset-archived"
             )

    assert {:error, :dashboard_archived} =
             Dashboards.save_dashboard_investigation_preset(
               "org-preset-archived",
               "mission-preset-archived",
               "dashboard-preset-archived",
               %{name: "Archived compare", payload: comparison_payload()}
             )

    assert {:error, :dashboard_not_found} =
             Dashboards.save_dashboard_investigation_preset(
               "org-preset-archived",
               "mission-preset-archived",
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
