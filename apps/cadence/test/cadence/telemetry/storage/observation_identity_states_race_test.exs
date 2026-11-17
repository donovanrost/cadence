defmodule Cadence.Telemetry.Storage.ObservationIdentityStatesRaceTest do
  @moduledoc """
  First-seen rule (11-17), concurrency: a batch's lock covers only rows that exist, so two writers
  can both find an identity new. Neither may raise on the unique key: the later one waits on the
  insert, then applies its sighting or decision to the committed row under its lock.

  Real (unboxed) transactions; each test's rows are deleted by its own mission on exit.
  """
  use Cadence.DataCase, async: false

  import Cadence.TestSupport.ObservationIdentityFixtures
  import Ecto.Query

  alias Cadence.OperationalEvents.EventRow
  alias Cadence.Repo
  alias Cadence.Telemetry.Storage.ObservationIdentityStates
  alias Cadence.Telemetry.Storage.ObservationIdentityStates.DecisionEventRow
  alias Cadence.Telemetry.Storage.ObservationIdentityStates.TelemetryObservationIdentityStateRow
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    mission_id = "mission-first-seen-race-#{System.unique_integer([:positive])}"

    on_exit(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        for schema <- [TelemetryObservationIdentityStateRow, DecisionEventRow, EventRow] do
          Repo.delete_all(from(row in schema, where: row.mission_id == ^mission_id))
        end
      end)
    end)

    %{mission_id: mission_id}
  end

  test "two batches for the same new identity: the second waits, then updates the row", %{
    mission_id: mission_id
  } do
    first = envelope(mission_id: mission_id, sample_id: "race-a", validity_state: :advisory)
    second = envelope(mission_id: mission_id, sample_id: "race-b", validity_state: :advisory)
    assert first.observation_identity_id == second.observation_identity_id

    holder = hold_batch(first)

    waiter =
      unboxed_async(fn ->
        ObservationIdentityStates.record_envelopes([second], publish_facts?: false)
      end)

    refute_receive {:done, _result}, 300
    send(holder.pid, :commit)
    assert_receive {:done, :ok}, 2_000
    assert {:ok, :ok} = Task.await(holder)
    Task.await(waiter)

    state = unboxed_fetch(first.observation_identity_id)
    assert state.advisory_count == 2
    assert state.latest_observation_id == second.observation_id
  end

  test "a decision racing a batch waits for its row, then decides on it", %{
    mission_id: mission_id
  } do
    sighting = envelope(mission_id: mission_id, sample_id: "race-seen", validity_state: :advisory)
    decided = envelope(mission_id: mission_id, sample_id: "race-decided")
    assert sighting.observation_identity_id == decided.observation_identity_id

    holder = hold_batch(sighting)
    fetch = fn _query, _opts -> {:ok, stored_sample(decided)} end

    waiter =
      unboxed_async(fn ->
        ObservationIdentityStates.apply_decision(
          decided.observation_identity_id,
          :mark_conflict,
          decision_opts(decided, fetch_sample_fun: fetch)
        )
      end)

    refute_receive {:done, _result}, 300
    send(holder.pid, :commit)
    assert_receive {:done, {:ok, state}}, 2_000
    assert {:ok, :ok} = Task.await(holder)
    Task.await(waiter)

    # The batch's row won the insert; the decision applied to it.
    assert state.validity_state == :conflict
    assert state.advisory_count == 1
    assert state.latest_observation_id == sighting.observation_id
    assert unboxed_fetch(decided.observation_identity_id).decision_event_id
  end

  # Records `envelope` in a real transaction that stays open until the test sends :commit.
  defp hold_batch(envelope) do
    test_pid = self()

    holder = Task.async(fn -> Sandbox.unboxed_run(Repo, fn -> hold(envelope, test_pid) end) end)

    assert_receive :held, 2_000
    holder
  end

  defp hold(envelope, test_pid) do
    Repo.transaction(fn ->
      :ok = ObservationIdentityStates.record_envelopes([envelope], publish_facts?: false)
      send(test_pid, :held)
      receive do: (:commit -> :ok)
    end)
  end

  defp unboxed_async(fun) do
    test_pid = self()

    Task.async(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        result = fun.()
        send(test_pid, {:done, result})
        result
      end)
    end)
  end

  defp unboxed_fetch(observation_identity_id) do
    Sandbox.unboxed_run(Repo, fn ->
      {:ok, state} = ObservationIdentityStates.fetch(observation_identity_id)
      state
    end)
  end
end
