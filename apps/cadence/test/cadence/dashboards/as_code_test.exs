defmodule Cadence.Dashboards.AsCodeTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{AsCode, Document}

  test "returns CI-readable validation metadata" do
    document = %Document{
      dashboard_id: "dashboard-ci",
      organization_id: "org-ci",
      mission_id: "mission-ci",
      name: "CI dashboard"
    }

    assert {:ok, json} = Cadence.Dashboards.export_bundle(document)

    assert {:ok, result} = AsCode.validate_content(json, "dashboards/ci.json")
    assert result.source == "dashboards/ci.json"
    assert result.dashboard_id == "dashboard-ci"
    assert result.schema_version == 1
  end

  test "reports integrity failures at the decode stage" do
    assert {:error, error} = AsCode.validate_content("not-json", "broken.json")
    assert error.path == "broken.json"
    assert error.stage == :decode_or_integrity
  end
end
