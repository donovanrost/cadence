defmodule Cadence.GroundNetworks.PredictedPassesScaleTest do
  @moduledoc """
  What predicted passes cost at 500 and 1,000 spacecraft × 15 stations × 7 days (#891): a full
  run, a one-spacecraft recompute and the prune. Excluded by default (`--include scale`); it
  prints the figures the PR and #177 state and asserts a bounded number of queries (inserts
  batched by 2,000 rows, nothing per spacecraft) and a full run under a minute.
  """
  use Cadence.DataCase, async: false

  @moduletag :scale
  @moduletag timeout: 1_800_000

  alias Cadence.Comms.{GroundStation, GroundStationStore}
  alias Cadence.GroundNetworks.{ElementSets, PredictedPasses}
  alias Cadence.SpacecraftStore.SpacecraftRow

  @now ~U[2026-11-27 00:00:00.000000Z]
  @actor %{"actor_kind" => "user", "user_id" => "scale"}

  # The benchmark's 15 stations (dev/pass-prediction-benchmark), 78°N to 72°S.
  @stations [
    {64.8, -147.7},
    {78.2, 15.4},
    {-72.0, 2.5},
    {35.4, -116.9},
    {40.4, -4.2},
    {-35.4, 149.0},
    {13.6, 144.9},
    {-25.9, 27.7},
    {19.0, -155.7},
    {67.9, 21.1},
    {-53.0, -70.9},
    {1.4, 103.8},
    {51.1, -114.0},
    {-33.1, -70.7},
    {33.0, 131.0}
  ]

  for fleet <- [500, 1_000] do
    test "#{fleet} spacecraft × 15 stations × 7 days" do
      measure(unquote(fleet))
    end
  end

  defp measure(fleet) do
    org = "org-predicted-scale-#{fleet}"
    mission = "mission-predicted-scale-#{fleet}"
    persist_mission_scope(org, mission)
    crafts = insert_spacecraft!(org, mission, fleet)
    for {at, i} <- Enum.with_index(@stations), do: station!(org, mission, i, at)
    submit_orbits!(org, mission, crafts)

    {full_us, {queries, {:ok, full}}} =
      :timer.tc(fn -> count_queries(fn -> PredictedPasses.run(org, mission, :full, @now) end) end)

    {one_us, {:ok, one}} =
      :timer.tc(fn ->
        PredictedPasses.run(org, mission, {:spacecraft, [hd(crafts)]}, DateTime.add(@now, 3600))
      end)

    {prune_us, {:ok, prune}} =
      :timer.tc(fn ->
        PredictedPasses.run(org, mission, :prune, DateTime.add(@now, 8 * 86_400))
      end)

    IO.puts(
      "predicted passes n=#{fleet} stations=15 days=7 schedulers=#{System.schedulers_online()}: " <>
        "full #{s(full_us)} s, #{full.inserted} rows, #{queries} queries; " <>
        "one spacecraft #{s(one_us)} s (#{one.deleted} replaced by #{one.inserted}); " <>
        "prune #{s(prune_us)} s (#{prune.deleted} rows)"
    )

    assert full.inserted > fleet * 15 * 7 * 2
    assert queries <= div(full.inserted, 2_000) + 30, "#{queries} queries"
    assert full_us < 60_000_000
  end

  defp submit_orbits!(org, mission, crafts) do
    crafts
    |> Enum.with_index()
    |> Enum.chunk_every(1_000)
    |> Enum.each(fn chunk ->
      items =
        for {craft, i} <- chunk do
          %{spacecraft_id: craft, input: {:omm, omm(i)}}
        end

      {:ok, _} =
        ElementSets.submit(org, mission, items, actor: @actor, source: "manual", now: @now)
    end)
  end

  # The benchmark's synthetic fleet: 500–600 km, 53° and 97.6°, spread node and anomaly.
  defp omm(i) do
    re = 6378.135
    xke = 60.0 / :math.sqrt(re ** 3 / 398_600.8)
    no_kozai = xke / :math.pow((re + 500.0 + rem(i * 37, 100)) / re, 1.5)

    %{
      "EPOCH" => "2026-11-26T12:00:00",
      "MEAN_MOTION" => no_kozai * 1440.0 / (2 * :math.pi()),
      "ECCENTRICITY" => 0.0005 + rem(i, 10) * 0.0001,
      "INCLINATION" => if(rem(i, 2) == 0, do: 53.0, else: 97.6),
      "RA_OF_ASC_NODE" => rem(i * 13, 360) * 1.0,
      "ARG_OF_PERICENTER" => rem(i * 7, 360) * 1.0,
      "MEAN_ANOMALY" => rem(i * 29, 360) * 1.0,
      "BSTAR" => 2.0e-5
    }
  end

  defp station!(org, mission, i, {lat, lon}) do
    {:ok, _} =
      GroundStationStore.persist_ground_station(
        org,
        GroundStation.new(%{
          ground_station_id: "ground_station_scale_#{i}",
          organization_id: org,
          mission_id: mission,
          display_name: "Station #{i}",
          location: %{latitude_deg: lat, longitude_deg: lon, height_m: 100.0}
        })
      )
  end

  defp insert_spacecraft!(org, mission, count) do
    at = DateTime.utc_now()

    rows =
      for i <- 1..count do
        %{
          spacecraft_id: "craft-scale-#{count}-#{i}",
          organization_id: org,
          mission_id: mission,
          display_name: "Scale #{i}",
          metadata: %{},
          lifecycle_state: "active",
          inserted_at: at
        }
      end

    {^count, _} = Repo.insert_all(SpacecraftRow, rows)
    Enum.map(rows, & &1.spacecraft_id)
  end

  defp count_queries(fun) do
    owner = self()
    handler = "predicted-passes-scale-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      handler,
      [:cadence, :repo, :query],
      fn _event, _measurements, _meta, _config -> if self() == owner, do: send(owner, :query) end,
      nil
    )

    try do
      result = fun.()
      {drain(0), result}
    after
      :telemetry.detach(handler)
    end
  end

  defp drain(n) do
    receive do
      :query -> drain(n + 1)
    after
      0 -> n
    end
  end

  defp s(us), do: Float.round(us / 1.0e6, 2)
end
