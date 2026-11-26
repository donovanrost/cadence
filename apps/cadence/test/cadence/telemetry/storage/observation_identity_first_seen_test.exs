defmodule Cadence.Telemetry.Storage.ObservationIdentityFirstSeenTest do
  @moduledoc """
  The first-seen rule (11-17): an identity-state row exists only for an identity something has
  been said about (a decision, or a non-canonical sighting). A decision on an identity without a
  row creates it from the stored observation, read before the decision's transaction opens.
  """
  use Cadence.DataCase, async: false

  import Cadence.TestSupport.ObservationIdentityFixtures

  alias Cadence.Repo
  alias Cadence.Telemetry.DataManagement
  alias Cadence.Telemetry.Storage
  alias Cadence.Telemetry.Storage.ObservationIdentityStates

  describe "record_envelopes/2" do
    test "a canonical first sighting writes no row" do
      envelope = envelope(sample_id: "fs-canonical")

      assert :ok = ObservationIdentityStates.record_envelopes([envelope], publish_facts?: false)

      assert {:error, :observation_identity_state_not_found} =
               ObservationIdentityStates.fetch(envelope.observation_identity_id)
    end

    test "a non-canonical first sighting writes its row" do
      envelope = envelope(sample_id: "fs-advisory", validity_state: :advisory)

      assert :ok = ObservationIdentityStates.record_envelopes([envelope], publish_facts?: false)
      assert {:ok, state} = ObservationIdentityStates.fetch(envelope.observation_identity_id)

      assert state.validity_state == :advisory
      assert state.advisory_count == 1
      assert state.canonical_count == 0
      assert state.canonical_observation_id == nil
      assert state.latest_observation_id == envelope.observation_id
    end

    test "a later sighting of an identity that has a row updates it" do
      advisory = envelope(sample_id: "fs-row-advisory", validity_state: :advisory)
      canonical = envelope(sample_id: "fs-row-canonical")
      assert advisory.observation_identity_id == canonical.observation_identity_id

      assert :ok = ObservationIdentityStates.record_envelopes([advisory], publish_facts?: false)
      assert :ok = ObservationIdentityStates.record_envelopes([canonical], publish_facts?: false)
      assert {:ok, state} = ObservationIdentityStates.fetch(canonical.observation_identity_id)

      assert state.validity_state == :canonical
      assert state.canonical_observation_id == canonical.observation_id
      assert state.latest_observation_id == canonical.observation_id
      assert state.canonical_count == 1
      assert state.advisory_count == 1
    end

    # #161: a replay that batches the journal differently carries the same sample and packet in
    # another evidence. It's the same observation, so an identity that has a row sees a no-op:
    # counts, latest and canonical stay as they were (a non-canonical row, and a decided one
    # whose latest sighting is canonical).
    test "a re-batched replay of an identity's latest sighting changes nothing" do
      advisory =
        envelope(sample_id: "fs-replay-advisory", validity_state: :advisory, point_id: "HK.a")

      first = envelope(sample_id: "fs-replay-first", validity_state: :advisory, point_id: "HK.b")
      canonical = envelope(sample_id: "fs-replay-canonical", point_id: "HK.b")

      for batch <- [[advisory, first], [canonical]],
          do:
            assert(:ok = ObservationIdentityStates.record_envelopes(batch, publish_facts?: false))

      before = states([advisory, canonical])

      replayed =
        for item <- [advisory, canonical] do
          envelope(
            sample_id: item.sample_id,
            point_id: item.observable_id,
            evidence_id: "evidence-rebatched",
            validity_state: item.validity_state
          )
        end

      assert [%{advisory_count: 1}, %{canonical_count: 1, advisory_count: 1}] = before
      assert :ok = ObservationIdentityStates.record_envelopes(replayed, publish_facts?: false)
      assert states([advisory, canonical]) == before
    end

    test "a batch of first sightings costs one locking read and no writes" do
      envelopes =
        for index <- 1..50, do: envelope(sample_id: "fs-batch-#{index}", point_id: "HK.p#{index}")

      statements =
        count_identity_state_statements(fn ->
          assert :ok =
                   ObservationIdentityStates.record_envelopes(envelopes, publish_facts?: false)
        end)

      assert statements == 1
      assert ObservationIdentityStates.list_for_selection("mission-first-seen") == []
    end
  end

  defp states(envelopes) do
    for envelope <- envelopes do
      {:ok, state} = ObservationIdentityStates.fetch(envelope.observation_identity_id)

      Map.take(state, [
        :canonical_count,
        :advisory_count,
        :latest_observation_id,
        :latest_sample_id,
        :canonical_observation_id,
        :validity_state
      ])
    end
  end

  describe "apply_decision/3 on an identity without a row" do
    test "creates the row from the stored observation, read before the transaction" do
      envelope = envelope(sample_id: "fs-decide")
      assert :ok = ObservationIdentityStates.record_envelopes([envelope], publish_facts?: false)
      fetch = fetch_sample_fun(self(), {:ok, stored_sample(envelope)})

      assert {:ok, state} =
               ObservationIdentityStates.apply_decision(
                 envelope.observation_identity_id,
                 :mark_conflict,
                 decision_opts(envelope, fetch_sample_fun: fetch)
               )

      assert_received {:fetch_sample, query, false}
      assert query.sample_id == envelope.sample_id
      assert query.point_id == envelope.point_id
      assert query.source_binding_id == envelope.binding_id
      assert DateTime.compare(query.from_observed_at, envelope.generation_time) == :eq
      assert DateTime.compare(query.to_observed_at, envelope.generation_time) == :eq

      assert state.validity_state == :conflict
      assert state.latest_observation_id == envelope.observation_id
      assert state.latest_sample_id == envelope.sample_id
      assert state.latest_revision == 1
      assert state.canonical_observation_id == envelope.observation_id
      assert state.canonical_count == 1
      assert state.point_id == envelope.point_id
      assert state.observable_id == envelope.observable_id

      assert [event] = decision_events(envelope)
      assert event.previous_state["validity_state"] == "canonical"
      assert event.new_state["validity_state"] == "conflict"
    end

    test "takes the revision from the stored row" do
      envelope = envelope(sample_id: "fs-revision", revision: 2)
      fetch = fetch_sample_fun(self(), {:ok, stored_sample(envelope)})

      assert {:ok, state} =
               ObservationIdentityStates.apply_decision(
                 envelope.observation_identity_id,
                 :mark_advisory,
                 decision_opts(envelope, fetch_sample_fun: fetch)
               )

      assert state.latest_revision == 2
      assert state.canonical_revision == 2
    end

    test "an identity that has a row never reads the store" do
      envelope = envelope(sample_id: "fs-has-row", validity_state: :advisory)
      assert :ok = ObservationIdentityStates.record_envelopes([envelope], publish_facts?: false)
      fetch = fn _query, _opts -> flunk("read the store for an identity that has a row") end

      assert {:ok, state} =
               ObservationIdentityStates.apply_decision(
                 envelope.observation_identity_id,
                 :mark_conflict,
                 decision_opts(envelope, fetch_sample_fun: fetch)
               )

      assert state.validity_state == :conflict
      assert state.advisory_count == 1
    end

    test "refuses to read the store inside an open transaction" do
      envelope = envelope(sample_id: "fs-in-transaction")
      fetch = fetch_sample_fun(self(), {:ok, stored_sample(envelope)})

      assert {:ok, {:error, :decision_lookup_inside_transaction}} =
               Repo.transaction(fn ->
                 ObservationIdentityStates.apply_decision(
                   envelope.observation_identity_id,
                   :mark_conflict,
                   decision_opts(envelope, fetch_sample_fun: fetch)
                 )
               end)

      refute_received {:fetch_sample, _query, _in_transaction?}
      assert_nothing_written(envelope)
    end

    test "writes nothing when the store can't be reached" do
      envelope = envelope(sample_id: "fs-offline")
      fetch = fetch_sample_fun(self(), {:error, :econnrefused})

      assert {:error, :econnrefused} =
               ObservationIdentityStates.apply_decision(
                 envelope.observation_identity_id,
                 :mark_conflict,
                 decision_opts(envelope, fetch_sample_fun: fetch)
               )

      assert_nothing_written(envelope)
    end

    test "writes nothing when the stored row disagrees with the decision" do
      envelope = envelope(sample_id: "fs-disagree")
      other = envelope(sample_id: "fs-other", point_id: "HK.other")
      stored = stored_sample(envelope)

      no_revision = put_in(stored.provenance["storage"]["revision"], nil)
      wrong_revision = put_in(stored.provenance["storage"]["revision"], 3)
      id = envelope.observation_identity_id

      for {result, expected} <- [
            {{:ok, stored_sample(other)}, {:observation_identity_mismatch, id}},
            {{:ok, no_revision}, {:missing_field, :revision}},
            {{:ok, wrong_revision}, {:observation_revision_mismatch, id}},
            {{:error, :not_found}, :not_found}
          ] do
        fetch = fetch_sample_fun(self(), result)

        assert {:error, ^expected} =
                 ObservationIdentityStates.apply_decision(
                   id,
                   :mark_conflict,
                   decision_opts(envelope, fetch_sample_fun: fetch)
                 )
      end

      assert_nothing_written(envelope)
    end

    test "needs the observation's point, sample and time, and reads nothing without them" do
      envelope = envelope(sample_id: "fs-missing")
      fetch = fetch_sample_fun(self(), {:ok, stored_sample(envelope)})

      for field <- [:point_id, :observed_at, :sample_id] do
        opts = envelope |> decision_opts(fetch_sample_fun: fetch) |> Keyword.delete(field)

        assert {:error, {:missing_field, ^field}} =
                 ObservationIdentityStates.apply_decision(
                   envelope.observation_identity_id,
                   :mark_conflict,
                   opts
                 )
      end

      refute_received {:fetch_sample, _query, _in_transaction?}
      assert_nothing_written(envelope)
    end
  end

  test "decision items carry the observation through data management" do
    envelope = envelope(sample_id: "fs-data-management")
    fetch = fetch_sample_fun(self(), {:ok, stored_sample(envelope)})

    item = %{
      observation_identity_id: envelope.observation_identity_id,
      point_id: envelope.point_id,
      sample_id: envelope.sample_id,
      observed_at: DateTime.to_iso8601(envelope.generation_time)
    }

    attrs = %{
      organization_id: envelope.organization_id,
      mission_id: envelope.mission_id,
      realm: envelope.realm,
      data_source_id: envelope.data_source_id,
      binding_id: envelope.binding_id,
      decision_reason: "operator_review"
    }

    assert {:ok, %{results: [result]}} =
             DataManagement.apply_observation_identity_decisions([item], :mark_conflict, attrs,
               decision_opts: [fetch_sample_fun: fetch, refresh_latest_value?: false]
             )

    assert result.validity_state == :conflict
    assert_received {:fetch_sample, _query, false}
  end

  defp decision_events(envelope) do
    Storage.list_observation_identity_decision_events(envelope.observation_identity_id,
      organization_id: envelope.organization_id,
      mission_id: envelope.mission_id
    )
  end

  defp assert_nothing_written(envelope) do
    assert {:error, :observation_identity_state_not_found} =
             ObservationIdentityStates.fetch(envelope.observation_identity_id)

    assert decision_events(envelope) == []
  end

  defp count_identity_state_statements(fun) do
    handler_id = "first-seen-statements-#{System.unique_integer([:positive])}"
    counter = :counters.new(1, [])

    :ok =
      :telemetry.attach(
        handler_id,
        [:cadence, :repo, :query],
        fn _event, _measurements, %{source: source}, _config ->
          if source == "telemetry_observation_identity_states", do: :counters.add(counter, 1, 1)
        end,
        nil
      )

    try do
      fun.()
    after
      :telemetry.detach(handler_id)
    end

    :counters.get(counter, 1)
  end
end
