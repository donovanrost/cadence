defmodule CadenceWeb.OpsDashboardShowLive.DataLinkPresentationEvidenceTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDashboardShowLive.DataLinkPresentation

  test "evidence falls back to inspector source context" do
    link = %{
      link_id: "telemetry_point:HK.counter:request-1",
      label: nil,
      target_text: "telemetry point",
      target_id: "HK.counter",
      context: %{}
    }

    inspector = %{
      source_context: %{
        realm: "flight",
        data_view: "derived",
        data_source_id: "questdb-flight",
        source_binding_id: "binding-flight",
        time_mode: "archive",
        time_axis: "receipt_time",
        replay_run_id: "replay-1"
      }
    }

    assert [row] = DataLinkPresentation.evidence([link], inspector)

    assert %{
             link_id: "telemetry_point:HK.counter:request-1",
             target: "",
             target_text: "telemetry point",
             target_id: "HK.counter",
             label: "telemetry point",
             realm: "flight",
             data_view: "derived",
             data_source_id: "questdb-flight",
             source_binding_id: "binding-flight",
             time_mode: "archive",
             time_axis: "receipt_time",
             replay_run_id: "replay-1"
           } = row
  end

  test "evidence link context wins over inspector fallback context" do
    link = %{
      "link_id" => "telemetry_point:HK.counter:request-1",
      "target" => "telemetry_point",
      "target_id" => "HK.counter",
      "context" => %{
        "data" => %{
          "realm" => "simulation",
          "data_source_id" => "questdb-sim"
        },
        "time" => %{
          "mode" => "live"
        }
      }
    }

    inspector = %{
      "source_context" => %{
        "realm" => "flight",
        "data_source_id" => "questdb-flight",
        "time_mode" => "archive"
      }
    }

    assert [row] = DataLinkPresentation.evidence([link], inspector)

    assert row.link_id == "telemetry_point:HK.counter:request-1"
    assert row.target == "telemetry_point"
    assert row.target_text == "telemetry point"
    assert row.target_id == "HK.counter"
    assert row.label == "telemetry point"
    assert row.realm == "simulation"
    assert row.data_source_id == "questdb-sim"
    assert row.time_mode == "live"
  end
end
