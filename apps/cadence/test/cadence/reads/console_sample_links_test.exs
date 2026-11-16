defmodule Cadence.Reads.ConsoleSampleLinksTest do
  @moduledoc "§11c(D) D2: evidence links open the sample in the console's Investigate."
  use Cadence.DataCase, async: false

  alias Cadence.Reads.ConsoleSampleLinks
  alias Cadence.Spacecraft

  @org "org-sample-links"
  @mission "mission-sample-links"

  setup do
    persist_mission_scope(@org, @mission)

    {:ok, craft} =
      Cadence.SpacecraftStore.persist_spacecraft(
        @org,
        Spacecraft.new(%{mission_id: @mission, display_name: "EARENDIL-312", scid: 312})
      )

    {:ok, no_scid} =
      Cadence.SpacecraftStore.persist_spacecraft(
        @org,
        Spacecraft.new(%{mission_id: @mission, display_name: "No SCID"})
      )

    %{links: ConsoleSampleLinks.context(@org, @mission), craft: craft, no_scid: no_scid}
  end

  defp decode(href) do
    [path, query] = String.split(href, "?", parts: 2)
    {path, URI.decode_query(query)}
  end

  test "a spacecraft's sample: fleet telemetry at its generation time, else its receipt time",
       c do
    generated = "2026-11-08T02:08:11.123456Z"
    received = "2026-11-08T02:08:12.000000Z"

    assert {"/console/#{@org}/#{@mission}/fleet/312/telemetry",
            %{"points" => "EPS.VBAT", "focus" => "EPS.VBAT", "at" => ^generated}} =
             decode(
               ConsoleSampleLinks.href(
                 c.links,
                 c.craft.spacecraft_id,
                 "EPS.VBAT",
                 generated,
                 received
               )
             )

    assert {_, %{"at" => ^received}} =
             decode(
               ConsoleSampleLinks.href(c.links, c.craft.spacecraft_id, "EPS.VBAT", nil, received)
             )
  end

  test "a mission state or a spacecraft without a SCID falls back to the point's telemetry", c do
    for spacecraft_id <- [nil, c.no_scid.spacecraft_id, "not-in-mission"] do
      assert {"/console/#{@org}/#{@mission}/telemetry", %{"p" => "EPS.VBAT"}} ==
               decode(ConsoleSampleLinks.href(c.links, spacecraft_id, "EPS.VBAT", nil, nil))
    end
  end

  test "unresolved slugs fall back to /console" do
    links = ConsoleSampleLinks.context("no-such-org", "no-such-mission")
    assert ConsoleSampleLinks.href(links, nil, "EPS.VBAT", nil, nil) == "/console"
  end
end
