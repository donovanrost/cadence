defmodule CadenceWeb.OpsDataSourcesLive.SourceFocusResourcesTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDataSourcesLive.{SourceFocus, SourceFocusResources}

  test "returns no presentation when the focus has no operational resources" do
    assert SourceFocusResources.build(
             SourceFocus.default(),
             SourceFocusResources.default(),
             fn _key, _value -> nil end
           ) == nil
  end

  test "infers station context from resolved endpoint metadata and builds resource rows" do
    resources =
      SourceFocusResources.default()
      |> Map.put(:source_endpoint, %{
        source_endpoint_id: "endpoint-alpha",
        display_name: "Goldstone DSS-14",
        source_ref: "provider/goldstone",
        metadata: %{"ground_station_id" => "dss-14"}
      })
      |> SourceFocusResources.put_inferred_ground_station("dss-14")

    assert resources.ground_station == %{
             id: "dss-14",
             label: "dss-14 / Goldstone DSS-14 / provider/goldstone",
             status: :inferred
           }

    focus =
      SourceFocus.from_params(%{
        "selected_target" => "source_endpoint",
        "selected_id" => "endpoint-alpha",
        "source_endpoint_id" => "endpoint-alpha",
        "ground_station_id" => "dss-14"
      })

    presentation =
      SourceFocusResources.build(focus, resources, fn key, value ->
        "/resource/#{key}/#{value}"
      end)

    assert %{selected_target: "source_endpoint", selected_id: "endpoint-alpha"} = presentation

    assert %{
             display_value: "Goldstone DSS-14 / provider/goldstone",
             status: "resolved",
             href: "/resource/source_endpoint_id/endpoint-alpha"
           } = row(presentation, "source_endpoint_id")

    assert %{
             display_value: "dss-14 / Goldstone DSS-14 / provider/goldstone",
             status: "inferred",
             status_text: "inferred"
           } = row(presentation, "ground_station_id")
  end

  test "marks a station without matching resource metadata as unverified" do
    resources =
      SourceFocusResources.default()
      |> SourceFocusResources.put_inferred_ground_station("dss-24")

    focus = SourceFocus.from_params(%{"ground_station_id" => "dss-24"})
    presentation = SourceFocusResources.build(focus, resources, fn _key, _value -> nil end)

    assert %{
             display_value: "dss-24",
             status: "unverified",
             status_text: "unverified"
           } = row(presentation, "ground_station_id")
  end

  test "preserves a fetched ground station instead of replacing it with fallback state" do
    ground_station = %{ground_station_id: "dss-14", display_name: "Goldstone"}
    resources = %{SourceFocusResources.default() | ground_station: ground_station}

    assert %{ground_station: ^ground_station} =
             SourceFocusResources.put_inferred_ground_station(resources, "dss-14")
  end

  defp row(presentation, key) do
    Enum.find(presentation.rows, &(&1.key == key))
  end
end
