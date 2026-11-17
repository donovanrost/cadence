defmodule Cadence.Alarms.EpisodeReplayIdsTest do
  @moduledoc """
  DECISIONS #99: a monitoring transition keyed on its input (journal frame or timer) writes its
  episode and event with replay-safe ids, insert-or-get. A replay after a crash finds them and
  changes nothing, whatever happened to the episode since; a different effect under a stored id is
  a hard error (MM_REPLAY_ID_CONFLICT).
  """
  use Cadence.DataCase, async: false

  import Cadence.ConfigurationFixtures
  import ExUnit.CaptureLog

  alias Cadence.Alarms.{EpisodeEventRow, EpisodeRow, Episodes}
  alias Cadence.Platform.ReplayId

  setup do
    %{mission_id: mission, organization_id: org} = configuration_mission("replay-ids")
    %{org: org, mission: mission, t0: DateTime.utc_now()}
  end

  test "the episode and its event take the input's replay-safe ids", ctx do
    raise_obs = observation(ctx, :caution, 0, "ref-a")
    assert {:ok, :changed} = Episodes.observe(Repo, raise_obs)

    assert [%{episode_id: episode_id}] = episodes(ctx)
    assert episode_id == ReplayId.id(:alarm_episode, raise_obs.effect_key)
    assert [%{event_id: event_id, kind: "raised"}] = events(ctx)
    assert event_id == ReplayId.id(:alarm_event, raise_obs.effect_key)
  end

  test "a replayed raise changes nothing, while open or after it moved on", ctx do
    raise_obs = observation(ctx, :caution, 0, "ref-a")
    {:ok, :changed} = Episodes.observe(Repo, raise_obs)

    # Replayed while the episode is still as it left it.
    assert {:ok, _} = Episodes.observe(Repo, raise_obs)
    assert [%{severity: "caution"}] = episodes(ctx)
    assert ["raised"] = Enum.map(events(ctx), & &1.kind)

    # Escalated by a later input, then the first input is replayed: the decision would be a
    # deescalation, but its event id is taken, so the episode keeps its later state.
    {:ok, :changed} = Episodes.observe(Repo, observation(ctx, :critical, 1, "ref-b"))
    assert {:ok, :unchanged} = Episodes.observe(Repo, raise_obs)
    assert [%{severity: "critical", state: "active"}] = episodes(ctx)
    assert ["raised", "escalated"] = Enum.map(events(ctx), & &1.kind)
  end

  test "a raise replayed after its episode cleared doesn't open a second one", ctx do
    raise_obs = observation(ctx, :caution, 0, "ref-a")
    {:ok, :changed} = Episodes.observe(Repo, raise_obs)
    {:ok, :changed} = Episodes.observe(Repo, observation(ctx, :normal, 1, "ref-b"))

    assert {:ok, :unchanged} = Episodes.observe(Repo, raise_obs)
    assert [%{state: "cleared"}] = episodes(ctx)
    assert ["raised", "cleared"] = Enum.map(events(ctx), & &1.kind)
  end

  test "a different input under a stored id is refused, not swallowed", ctx do
    {:ok, :changed} = Episodes.observe(Repo, observation(ctx, :caution, 0, "ref-a"))

    # Same key (a bug: two inputs mapped to one id), another source record.
    impostor = %{observation(ctx, :critical, 0, "ref-other") | effect_key: key(ctx, 0)}

    log =
      capture_log(fn ->
        assert {:error, {:replay_id_conflict, :alarm_event, _id}} =
                 Episodes.observe(Repo, impostor)
      end)

    assert log =~ "MM_REPLAY_ID_CONFLICT"
  end

  test "an observation without a key works as before", ctx do
    plain = Map.delete(observation(ctx, :caution, 0, "ref-plain"), :effect_key)
    assert {:ok, :changed} = Episodes.observe(Repo, plain)
    assert {:ok, :unchanged} = Episodes.observe(Repo, plain)

    assert [%{episode_id: "alarm_episode_" <> _}] = episodes(ctx)
    assert [%{event_id: "alarm_event_" <> _}] = events(ctx)
  end

  defp observation(ctx, level, n, ref) do
    at = DateTime.add(ctx.t0, n, :millisecond)

    %{
      source: "catalog_monitoring",
      organization_id: ctx.org,
      mission_id: ctx.mission,
      spacecraft_id: nil,
      subject_key: "VBAT/policy-1",
      parameter_ref: "VBAT",
      point_name: "VBAT",
      level: level,
      source_state: Atom.to_string(level),
      value: 23.1,
      observed_at: at,
      evaluated_at: at,
      ref: ref,
      effect_key: key(ctx, n)
    }
  end

  # One journal frame per input: offset n * 14, index 0.
  defp key(ctx, n),
    do: %{receipt: DateTime.add(ctx.t0, n, :millisecond), ordinal: 1, offset: n * 14, index: 0}

  defp episodes(ctx),
    do: Repo.all(from(e in EpisodeRow, where: e.mission_id == ^ctx.mission))

  defp events(ctx),
    do:
      Repo.all(
        from(e in EpisodeEventRow,
          where: e.mission_id == ^ctx.mission,
          order_by: [asc: e.at, asc: e.event_id]
        )
      )
end
