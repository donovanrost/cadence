defmodule CadenceWeb.OpsDashboardShowLive.DataLinkIndexTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{DataLink, Field, Frame, PlacementFrames}
  alias CadenceWeb.OpsDashboardShowLive.DataLinkIndex

  test "collects links from panel, engine warnings, primary frames, overlays, and field metadata" do
    panel_link = link("panel-link", :telemetry_point, "HK.panel")
    warning_link = link("warning-link", :limit_event, "limit-1")
    frame_link = link("frame-link", :telemetry_sample, "sample-1")
    field_link = link("field-link", :telemetry_point, "HK.field")
    overlay_link = link("overlay-link", :contact, "contact-1")
    standalone_link = link("standalone-link", :mission_event, "mission-event-1")

    placement_frames =
      placement_frames(
        primary: [frame([frame_link], [field_link])],
        overlays: %{"limits" => [frame([overlay_link], [])]},
        warnings: [%{links: [warning_link]}]
      )

    index = %{
      panel: {:data_link, %{related_links: [panel_link, %{not: "a link"}]}},
      engine_result: %{
        dashboard_warnings: [%{"links" => [warning_link]}],
        frames_by_placement: %{"placement-1" => placement_frames}
      },
      frames_by_placement: %{
        "placement-2" => placement_frames(primary: [frame([standalone_link], [])])
      }
    }

    assert DataLinkIndex.all_links(index) == [
             panel_link,
             warning_link,
             warning_link,
             frame_link,
             field_link,
             overlay_link,
             standalone_link
           ]
  end

  test "finds selected link in the query placement before global links" do
    global_link = link("shared-link", :telemetry_point, "HK.global")
    placement_link = link("shared-link", :telemetry_point, "HK.placement")

    index = %{
      panel: {:data_link, %{related_links: [global_link]}},
      engine_result: nil,
      frames_by_placement: %{
        "placement-1" => placement_frames(primary: [frame([placement_link], [])])
      }
    }

    assert DataLinkIndex.find_link_from_query(index, %{
             "selected_link" => "shared-link",
             "selected_placement" => "placement-1"
           }) == placement_link
  end

  test "finds selected target in placement links before global links" do
    global_link = link("global-link", :telemetry_point, "HK.counter")
    placement_link = link("placement-link", :telemetry_point, "HK.counter")

    index = %{
      panel: {:data_link, %{related_links: [global_link]}},
      engine_result: nil,
      frames_by_placement: %{
        "placement-1" => placement_frames(primary: [frame([placement_link], [])])
      }
    }

    assert DataLinkIndex.find_link_from_query(index, %{
             "selected_target" => "telemetry_point",
             "selected_id" => "HK.counter",
             "selected_placement" => "placement-1"
           }) == placement_link
  end

  test "falls back to synthetic links for resolvable direct target queries" do
    assert %DataLink{
             link_id: "direct:telemetry_point:HK.counter",
             target: :telemetry_point,
             target_id: "HK.counter",
             source: :annotation
           } =
             DataLinkIndex.find_link_from_query(%{}, %{
               "selected_target" => "telemetry_point",
               "selected_id" => "HK.counter"
             })
  end

  test "falls back to synthetic source-watermark event links with source context" do
    assert %DataLink{
             link_id: "direct:source_watermark_event:watermark-event-1",
             target: :source_watermark_event,
             target_id: "watermark-event-1",
             source: :annotation,
             context: %{
               time: %{mode: "archive", axis: "occurred_at"},
               data: %{
                 realm: "flight",
                 data_source_id: "events-projection",
                 source_binding_id: "events-binding"
               },
               selection: %{placement_id: "placement-1", timestamp_ms: 12_345}
             }
           } =
             DataLinkIndex.find_link_from_query(%{}, %{
               "selected_target" => "source_watermark_event",
               "selected_id" => "watermark-event-1",
               "selected_placement" => "placement-1",
               "selected_time" => 12_345,
               "realm" => "flight",
               "data_source_id" => "events-projection",
               "source_binding_id" => "events-binding",
               "time_mode" => "archive",
               "time_axis" => "occurred_at"
             })
  end

  defp placement_frames(attrs) do
    attrs
    |> Enum.into(%{primary: [], overlays: %{}, warnings: []})
    |> PlacementFrames.new()
  end

  defp frame(meta_links, field_links) do
    Frame.new(%{
      source: :telemetry,
      shape: :wide,
      meta: %{links: meta_links},
      fields: [
        Field.new(%{
          name: "counter",
          kind: :number,
          metadata: %{"links" => field_links}
        })
      ]
    })
  end

  defp link(link_id, target, target_id) do
    %DataLink{
      link_id: link_id,
      label: link_id,
      target: target,
      target_id: target_id,
      source: :field
    }
  end
end
