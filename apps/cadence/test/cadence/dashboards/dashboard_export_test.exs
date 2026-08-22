defmodule Cadence.Dashboards.DashboardExportTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.Document

  test "governed export round-trips binding semantics and rejects tampering" do
    document = %Document{
      dashboard_id: "dashboard-flight-power",
      organization_id: "org-flight",
      mission_id: "mission-flight",
      name: "Flight power",
      defaults: %{"time" => %{"mode" => "live"}},
      metadata: %{"version" => 7}
    }

    assert {:ok, json} =
             Cadence.Dashboards.export_bundle(document,
               exported_at: ~U[2026-08-01 12:00:00Z],
               exported_by: "user-1"
             )

    assert {:ok, %Document{} = decoded} = Cadence.Dashboards.validate_export_bundle(json)
    assert decoded.dashboard_id == document.dashboard_id
    assert decoded.defaults == document.defaults

    bundle = Jason.decode!(json)
    tampered = put_in(bundle, ["document", "defaults", "time", "mode"], "archive")

    assert {:error, :dashboard_export_binding_semantics_mismatch} =
             tampered |> Jason.encode!() |> Cadence.Dashboards.validate_export_bundle()
  end

  test "legacy raw documents remain valid import inputs" do
    document = %Document{
      dashboard_id: "dashboard-legacy",
      organization_id: "org-legacy",
      mission_id: "mission-legacy",
      name: "Legacy raw document"
    }

    assert {:ok, json} = Cadence.Dashboards.export_document(document)

    assert {:ok, %Document{name: "Legacy raw document"}} =
             Cadence.Dashboards.validate_export_bundle(json)
  end
end
