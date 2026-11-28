defmodule Cadence.GroundNetworks.PredictedPassesTest do
  @moduledoc """
  Predicted passes (#891): the recompute runs, their scope, the horizon extension at a pass that
  crosses the old horizon, the prune, the daily runs and the jobs that ask for each.
  """
  use Cadence.DataCase, async: true

  import Ecto.Query

  alias Cadence.Comms.{GroundStation, GroundStationStore, StationLocations}
  alias Cadence.GroundNetworks.{ElementSets, PredictedPasses}
  alias Cadence.GroundNetworks.PredictedPasses.{PredictedPassRow, Store}
  alias Cadence.Jobs.BackgroundJobRow
  alias Cadence.Platform.ScopedReadUpdates
  alias Cadence.Repo
  alias Cadence.SpacecraftStore
  alias Cadence.SpacecraftStore.SpacecraftRow

  @now ~U[2026-11-27 00:00:00.000000Z]
  @day 86_400
  @actor %{"actor_kind" => "user", "user_id" => "user-predicted-passes"}

  setup do
    suffix = System.unique_integer([:positive])
    org = "org-predicted-#{suffix}"
    mission = "mission-predicted-#{suffix}"
    persist_mission_scope(org, mission)
    [a, b, deep] = insert_spacecraft!(org, mission, 3)

    svalbard = station!(org, mission, "svalbard", {78.23, 15.41})
    hawaii = station!(org, mission, "hawaii", {19.01, -155.66})
    _unlocated = station!(org, mission, "unlocated", nil)

    {:ok, _} =
      ElementSets.submit(
        org,
        mission,
        [
          %{spacecraft_id: a, input: {:omm, omm(15.2, 97.6, 10.0)}},
          %{spacecraft_id: b, input: {:omm, omm(15.1, 97.6, 190.0)}},
          %{spacecraft_id: deep, input: {:omm, omm(2.0, 10.0, 0.0)}}
        ],
        actor: @actor,
        source: "manual",
        now: @now
      )

    %{org: org, mission: mission, a: a, b: b, deep: deep, svalbard: svalbard, hawaii: hawaii}
  end

  test "storing the first sets asks for one recompute of every spacecraft that got one", c do
    assert [%{payload: %{"kind" => "spacecraft", "spacecraft_ids" => ids}}] = jobs(c)
    assert Enum.sort(ids) == Enum.sort([c.a, c.b, c.deep])
  end

  test "a full run predicts every located station and records what it could not", c do
    assert {:ok, %{run: :full, inserted: inserted}} = run(c, :full, @now)
    assert inserted > 0

    passes = passes(c)
    assert length(passes) == inserted

    assert passes |> Enum.map(& &1.spacecraft_id) |> Enum.uniq() |> Enum.sort() ==
             Enum.sort([c.a, c.b])

    assert passes |> Enum.map(& &1.ground_station_id) |> Enum.uniq() |> Enum.sort() ==
             Enum.sort([c.svalbard, c.hawaii])

    horizon_end = DateTime.add(@now, 7 * @day)

    for pass <- passes do
      assert DateTime.compare(pass.los, @now) == :gt and
               DateTime.compare(pass.aos, horizon_end) == :lt

      assert DateTime.compare(pass.aos, pass.tca) != :gt and
               DateTime.compare(pass.tca, pass.los) != :gt

      assert pass.max_elevation_deg >= 5.0
    end

    state = Store.state(c.org, c.mission)
    assert state.horizon_end == horizon_end
    assert state.unpropagated == %{c.deep => "deep_space_not_supported"}
  end

  test "a new current element set replaces only that spacecraft's passes from now on", c do
    {:ok, _} = run(c, :full, @now)
    later = DateTime.add(@now, 3600 * 6)
    others = ids(c, c.b)
    {ended, open} = Enum.split_with(passes(c, c.a), &(DateTime.compare(&1.los, later) != :gt))
    assert ended != [] and open != []

    {:ok, [{:created, set}]} =
      ElementSets.submit(
        c.org,
        c.mission,
        [%{spacecraft_id: c.a, input: {:omm, omm(15.25, 97.6, 40.0, "2026-11-27T05:00:00")}}],
        actor: @actor,
        source: "manual",
        now: later
      )

    assert Enum.any?(
             jobs(c),
             &(&1.payload == %{
                 "kind" => "spacecraft",
                 "spacecraft_ids" => [c.a],
                 "organization_id" => c.org
               })
           )

    assert {:ok, %{run: :spacecraft, deleted: deleted}} = run(c, {:spacecraft, [c.a]}, later)
    assert deleted == length(open)
    assert ids(c, c.b) == others

    now_a = passes(c, c.a)

    assert MapSet.subset?(
             MapSet.new(Enum.map(ended, & &1.predicted_pass_id)),
             MapSet.new(Enum.map(now_a, & &1.predicted_pass_id))
           )

    for pass <- now_a,
        DateTime.compare(pass.los, later) == :gt,
        do: assert(pass.element_set_id == set.element_set_id)
  end

  test "an older element set doesn't ask for a recompute", c do
    before = length(jobs(c))

    {:ok, [{:created, _older}]} =
      ElementSets.submit(
        c.org,
        c.mission,
        [%{spacecraft_id: c.a, input: {:omm, omm(15.2, 97.6, 10.0, "2026-11-20T00:00:00")}}],
        actor: @actor,
        source: "manual",
        now: @now
      )

    assert length(jobs(c)) == before
  end

  test "a station change recomputes only that station, and an archived one loses its passes", c do
    {:ok, _} = run(c, :full, @now)
    hawaii = ids_at(c, c.hawaii)
    svalbard_count = length(ids_at(c, c.svalbard))

    {:ok, _} =
      GroundStationStore.update_ground_station(c.org, c.mission, c.svalbard, %{
        elevation_mask_deg: 30.0
      })

    assert {:ok, %{run: :stations}} = run(c, {:stations, [c.svalbard]}, @now)
    assert ids_at(c, c.hawaii) == hawaii
    assert length(ids_at(c, c.svalbard)) < svalbard_count

    {:ok, _} = GroundStationStore.archive_ground_station(c.org, c.mission, c.svalbard)
    assert {:ok, _} = run(c, {:stations, [c.svalbard]}, @now)
    assert ids_at(c, c.svalbard) == []
  end

  test "a provider's new location for an unlocated station asks for its recompute", c do
    [unlocated] =
      for s <- GroundStationStore.list_ground_stations(c.org, c.mission),
          s.location == nil,
          do: s.ground_station_id

    report = [
      %{"id" => unlocated, "location" => %{"latitude_deg" => -72.0, "longitude_deg" => 2.5}}
    ]

    {:ok, _} = StationLocations.record_provider_reports(c.org, c.mission, "sim", report, @now)

    assert [%{payload: %{"ground_station_ids" => [^unlocated]}}] =
             Enum.filter(jobs(c), &(&1.payload["kind"] == "station"))
  end

  test "the horizon extension stores a pass that crosses the old horizon once", c do
    {:ok, _} = run(c, :full, @now)
    old_end = Store.state(c.org, c.mission).horizon_end
    crossing = Enum.filter(passes(c), &crosses?(&1, old_end))

    next_day = DateTime.add(@now, @day)
    assert {:ok, %{run: :extend}} = run(c, :extend, next_day)
    assert Store.state(c.org, c.mission).horizon_end == DateTime.add(next_day, 7 * @day)

    after_crossing = Enum.filter(passes(c), &crosses?(&1, old_end))
    assert length(after_crossing) == length(crossing)

    # No two stored passes of one spacecraft over one station overlap.
    for {_pair, list} <- Enum.group_by(passes(c), &{&1.spacecraft_id, &1.ground_station_id}),
        [x, y] <- Enum.chunk_every(Enum.sort_by(list, & &1.aos, DateTime), 2, 1, :discard),
        do: assert(DateTime.compare(x.los, y.aos) != :gt)
  end

  test "the prune deletes passes that ended more than 7 days ago", c do
    {:ok, _} = run(c, :full, @now)
    total = length(passes(c))
    a_week_on = DateTime.add(@now, 8 * @day)
    {:ok, %{run: :prune, deleted: deleted}} = run(c, :prune, a_week_on)
    assert deleted > 0 and length(passes(c)) == total - deleted

    for pass <- passes(c),
        do: assert(DateTime.compare(pass.los, DateTime.add(a_week_on, -7 * @day)) != :lt)
  end

  test "archiving a spacecraft removes its future passes and leaves the others'", c do
    {:ok, _} = run(c, :full, @now)
    others = ids(c, c.b)
    later = DateTime.add(@now, 3600 * 6)
    ended = c |> passes(c.a) |> Enum.filter(&(DateTime.compare(&1.los, later) != :gt))

    {:ok, _} = SpacecraftStore.archive_spacecraft(c.org, c.mission, c.a, @actor)

    assert Enum.any?(
             jobs(c),
             &(&1.payload["kind"] == "spacecraft" and &1.payload["spacecraft_ids"] == [c.a])
           )

    :ok = ScopedReadUpdates.subscribe(:predicted_passes_changed, c.org, c.mission)
    assert {:ok, %{run: :spacecraft, inserted: 0}} = run(c, {:spacecraft, [c.a]}, later)
    assert_receive {:predicted_passes_changed, _, _}

    assert ids(c, c.b) == others
    # Passes that already ended stay for history until the prune.
    assert Enum.map(passes(c, c.a), & &1.predicted_pass_id) ==
             Enum.map(ended, & &1.predicted_pass_id)

    refute Map.has_key?(Store.state(c.org, c.mission).unpropagated, c.a)
  end

  test "full runs and horizon extensions skip an archived spacecraft", c do
    {:ok, _} = SpacecraftStore.archive_spacecraft(c.org, c.mission, c.a, @actor)
    {:ok, _} = run(c, :full, @now)
    assert passes(c, c.a) == [] and passes(c, c.b) != []

    {:ok, _} = run(c, :extend, DateTime.add(@now, @day))
    assert passes(c, c.a) == []
  end

  test "every finished run publishes the read update, even one that changed nothing", c do
    {:ok, _} = run(c, :full, @now)
    :ok = ScopedReadUpdates.subscribe(:predicted_passes_changed, c.org, c.mission)

    assert {:ok, %{deleted: 0, inserted: 0}} =
             run(c, {:stations, ["ground_station_missing"]}, @now)

    assert_receive {:predicted_passes_changed, _, _}

    assert {:ok, %{run: :prune, deleted: 0}} = run(c, :prune, @now)
    refute_receive {:predicted_passes_changed, _, _}
  end

  test "a repeat full recompute while one is open answers that run", c do
    {:ok, first} = PredictedPasses.enqueue_full(c.org, c.mission)
    {:ok, again} = PredictedPasses.enqueue_full(c.org, c.mission)
    assert again.run_id == first.run_id
    assert Enum.count(jobs(c), &(&1.payload["kind"] == "full")) == 1
  end

  test "a spacecraft run on a mission with no state runs in full", c do
    assert {:ok, %{run: :full}} = run(c, {:spacecraft, [c.a]}, @now)
    assert passes(c, c.b) != []
  end

  test "the daily runs are enqueued once per mission and day, and run as jobs", c do
    {:ok, _} = run(c, :full, @now)
    before = length(jobs(c))

    :ok = PredictedPasses.daily(@now)
    :ok = PredictedPasses.daily(DateTime.add(@now, 3600))
    daily = jobs(c) |> Enum.drop(before)
    assert daily |> Enum.map(& &1.payload["kind"]) |> Enum.sort() == ["extend", "prune"]

    for job <- daily,
        do: assert({:ok, %{}} = PredictedPasses.execute_enqueued_run(job.run_id))
  end

  defp run(c, kind, now), do: PredictedPasses.run(c.org, c.mission, kind, now)

  defp passes(c, spacecraft_id \\ nil) do
    PredictedPassRow
    |> where([p], p.mission_id == ^c.mission)
    |> then(&if(spacecraft_id, do: where(&1, [p], p.spacecraft_id == ^spacecraft_id), else: &1))
    |> order_by([p], asc: p.aos, asc: p.predicted_pass_id)
    |> Repo.all()
  end

  defp ids(c, spacecraft_id), do: c |> passes(spacecraft_id) |> Enum.map(& &1.predicted_pass_id)

  defp ids_at(c, station_id) do
    c
    |> passes()
    |> Enum.filter(&(&1.ground_station_id == station_id))
    |> Enum.map(& &1.predicted_pass_id)
  end

  defp crosses?(pass, time),
    do: DateTime.compare(pass.aos, time) == :lt and DateTime.compare(pass.los, time) == :gt

  defp jobs(c) do
    BackgroundJobRow
    |> where([j], j.mission_id == ^c.mission and j.job_type == "pass_prediction")
    |> order_by([j], asc: j.inserted_at, asc: j.job_id)
    |> Repo.all()
    |> Enum.map(&BackgroundJobRow.to_domain/1)
  end

  defp station!(org, mission, name, at) do
    location =
      case at do
        {lat, lon} -> %{latitude_deg: lat, longitude_deg: lon, height_m: 0.0}
        nil -> nil
      end

    id = "ground_station_#{name}_#{System.unique_integer([:positive])}"

    {:ok, _} =
      GroundStationStore.persist_ground_station(
        org,
        GroundStation.new(%{
          ground_station_id: id,
          organization_id: org,
          mission_id: mission,
          display_name: name,
          location: location
        })
      )

    id
  end

  defp omm(mean_motion, inclination, raan, epoch \\ "2026-11-26T12:00:00") do
    %{
      "EPOCH" => epoch,
      "MEAN_MOTION" => mean_motion,
      "ECCENTRICITY" => 0.0005,
      "INCLINATION" => inclination,
      "RA_OF_ASC_NODE" => raan,
      "ARG_OF_PERICENTER" => 90.0,
      "MEAN_ANOMALY" => 270.0,
      "BSTAR" => 2.0e-5
    }
  end

  defp insert_spacecraft!(org, mission, count) do
    at = DateTime.utc_now()
    suffix = System.unique_integer([:positive])

    rows =
      for i <- 1..count do
        %{
          spacecraft_id: "craft-#{suffix}-#{i}",
          organization_id: org,
          mission_id: mission,
          display_name: "Craft #{i}",
          scid: 100 + i,
          metadata: %{},
          lifecycle_state: "active",
          inserted_at: at
        }
      end

    {^count, _} = Repo.insert_all(SpacecraftRow, rows)
    Enum.map(rows, & &1.spacecraft_id)
  end
end
