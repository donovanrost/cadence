defmodule Cadence.Telemetry.Storage.IdentitySelectionByIdTest do
  @moduledoc """
  qa 11-14: a telemetry history read loaded every identity state of its point (a full scan of
  telemetry_observation_identity_states, 29 s on the dev data) to select canonical samples. It now
  loads only the states of the identities its rows carry. These pin that the selection is the
  same as with the full query, on mixed data: plain canonical identities, a revision correction,
  an operator-decided conflict, an operator exclusion, and states of other spacecraft and points.
  """
  use Cadence.DataCase, async: false

  alias Cadence.Telemetry.{EffectiveSelection, Sample}
  alias Cadence.Telemetry.Storage
  alias Cadence.Telemetry.Storage.{ObservationEnvelope, ObservationIdentityStates, WriteContext}
  alias Cadence.Telemetry.Storage.QuestDB.ObservationReader

  @mission "mission-sel"
  @context [
    organization_id: "org-sel",
    realm: :flight,
    data_source_id: "ds-primary",
    binding_id: "binding-v1"
  ]
  @filters @context ++ [point_id: "HK.mode", spacecraft_id: "sc-1"]

  setup do
    plain = for minute <- 1..3, do: envelope("plain-#{minute}", minute: minute)

    initial = envelope("corrected-r1", minute: 4)

    correction =
      envelope("corrected-r2",
        minute: 4,
        revision: 2,
        raw_value: 7,
        supersedes_observation_id: initial.observation_id
      )

    decided = envelope("decided-canonical", minute: 5)
    decided_conflict = envelope("decided-conflict", minute: 5, validity_state: :conflict)
    excluded = envelope("excluded", minute: 6)

    others = [
      envelope("other-spacecraft", minute: 1, spacecraft_id: "sc-2"),
      envelope("other-point", minute: 1, point_id: "HK.other")
    ]

    envelopes = plain ++ [initial, correction, decided, decided_conflict, excluded] ++ others
    assert :ok = ObservationIdentityStates.record_envelopes(envelopes)

    decide!(decided, :mark_canonical,
      canonical_observation_id: decided_conflict.observation_id,
      canonical_sample_id: decided_conflict.sample_id,
      canonical_revision: decided_conflict.revision
    )

    decide!(excluded, :mark_superseded, [])

    # The QuestDB rows a read of HK.mode on sc-1 returns: every physical observation of the point.
    rows = plain ++ [initial, correction, decided, decided_conflict, excluded]
    %{rows: rows, samples: Enum.map(rows, &physical_sample/1)}
  end

  test "states of the rows' identities select exactly what the full query selects", %{
    samples: samples
  } do
    full = ObservationIdentityStates.list_for_selection(@mission, @filters)
    by_id = by_id(samples)

    # First-seen rule (11-17): only decided identities have rows (decided, excluded); the plain
    # and corrected sightings, and the other spacecraft and point, wrote none.
    assert length(by_id) == 2
    assert length(full) == 2

    selected = selected(samples, full)
    assert selected(samples, by_id) == selected

    # The data is mixed enough to matter: the operator's decisions change what's selected (a
    # revision without a decision is left to the rows' own validity state).
    ids = Enum.map(selected, & &1.sample_id)
    assert "corrected-r2" in ids
    assert "decided-conflict" in ids
    refute "decided-canonical" in ids
    refute "excluded" in ids
  end

  test "a window of the rows selects the same as the full query does for that window", %{
    samples: samples
  } do
    window = Enum.filter(samples, &(&1.sample_id =~ ~r/^(decided|excluded|plain-2)/))
    full = ObservationIdentityStates.list_for_selection(@mission, @filters)

    # decided and excluded have rows; plain-2 (a canonical sighting) has none.
    assert length(by_id(window)) == 2
    assert selected(window, by_id(window)) == selected(window, full)
  end

  test "no identity ids load no states" do
    assert [] =
             ObservationIdentityStates.list_for_selection(
               @mission,
               [observation_identity_ids: [nil, ""]] ++ @filters
             )
  end

  test "the history read applies the stored decisions through the id lookup", %{
    rows: rows,
    samples: samples
  } do
    exec_fun = fn _sql, _opts ->
      {:ok,
       %{
         "columns" => Enum.map(ObservationReader.select_columns(), &%{"name" => &1}),
         "dataset" => Enum.map(rows, &questdb_row/1)
       }}
    end

    assert {:ok, %{samples: read}} =
             ObservationReader.sample_history_result(
               @mission,
               "HK.mode",
               [exec_fun: exec_fun, spacecraft_id: "sc-1", limit: 50] ++ @context
             )

    full = ObservationIdentityStates.list_for_selection(@mission, @filters)
    assert Enum.map(read, & &1.sample_id) == Enum.map(selected(samples, full), & &1.sample_id)
  end

  defp by_id(samples) do
    ids = Enum.map(samples, & &1.provenance["storage"]["observation_identity_id"])

    ObservationIdentityStates.list_for_selection(
      @mission,
      [observation_identity_ids: ids] ++ @filters
    )
  end

  defp selected(samples, states), do: EffectiveSelection.selected_samples(samples, states, [])

  defp decide!(envelope, decision, extra) do
    assert {:ok, _state} =
             Storage.apply_observation_identity_decision(
               envelope.observation_identity_id,
               decision,
               [
                 organization_id: envelope.organization_id,
                 mission_id: envelope.mission_id,
                 realm: envelope.realm,
                 data_source_id: envelope.data_source_id,
                 binding_id: envelope.binding_id,
                 decision_reason: "operator_#{decision}",
                 decided_at: ~U[2026-06-22 12:10:00Z],
                 operator_id: "ops-1",
                 # First-seen rule: an identity without a row is decided from its stored row.
                 point_id: envelope.point_id,
                 sample_id: envelope.sample_id,
                 observed_at: envelope.generation_time || envelope.receipt_time,
                 fetch_sample_fun: fn _query, _opts ->
                   {:ok, ObservationEnvelope.to_sample(envelope)}
                 end
               ] ++ extra
             )
  end

  # The sample a QuestDB row of this observation reads back as (ObservationReader.sample_from_row).
  defp physical_sample(envelope) do
    envelope
    |> questdb_row()
    |> then(&Enum.zip(ObservationReader.select_columns(), &1))
    |> Map.new()
    |> ObservationReader.sample_from_row()
  end

  defp questdb_row(envelope) do
    values = %{
      "sample_id" => envelope.sample_id,
      "mission_id" => envelope.mission_id,
      "spacecraft_id" => envelope.spacecraft_id,
      "point_id" => envelope.point_id,
      "point_name" => envelope.point_name,
      "packet_definition_id" => envelope.packet_definition_id,
      "packet_definition_version" => envelope.packet_definition_version,
      "packet_id" => "packet-" <> envelope.sample_id,
      "evidence_id" => "evidence-" <> envelope.sample_id,
      "value_kind" => "long",
      "value_long" => 1,
      "raw_value_text" => Jason.encode!(%{"counts" => 1}),
      "quality_state" => "good",
      "generation_time" => DateTime.to_naive(envelope.generation_time),
      "receipt_time" => ~N[2026-06-22 12:00:00],
      "provenance_json" => "{}",
      "realm" => "flight",
      "data_source_id" => envelope.data_source_id,
      "binding_id" => envelope.binding_id,
      "source_endpoint_id" => "station-a",
      "observation_id" => envelope.observation_id,
      "observation_identity_id" => envelope.observation_identity_id,
      "validity_state" => to_string(envelope.validity_state)
    }

    Enum.map(ObservationReader.select_columns(), &Map.get(values, &1))
  end

  defp envelope(sample_id, overrides) do
    {:ok, context} =
      WriteContext.new(
        @context ++
          [
            mission_id: @mission,
            source_endpoint_id: "station-a",
            recorded_at: ~U[2026-06-22 12:00:00Z],
            metadata: %{}
          ]
      )

    point_id = Keyword.get(overrides, :point_id, "HK.mode")
    raw_value = Keyword.get(overrides, :raw_value, 1)

    sample = %Sample{
      sample_id: sample_id,
      mission_id: @mission,
      spacecraft_id: Keyword.get(overrides, :spacecraft_id, "sc-1"),
      point_id: point_id,
      point_name: point_id,
      packet_definition_id: "packet-def-1",
      packet_definition_version: 1,
      packet_id: "packet-" <> sample_id,
      evidence_id: "evidence-" <> sample_id,
      raw_value: raw_value,
      engineering_value: raw_value,
      quality_state: :good,
      generation_time: DateTime.add(~U[2026-06-22 11:00:00Z], overrides[:minute], :minute),
      receipt_time: ~U[2026-06-22 12:00:00Z],
      provenance: %{}
    }

    {:ok, envelope} =
      ObservationEnvelope.from_sample(context, sample,
        validity_state: Keyword.get(overrides, :validity_state, :canonical),
        revision: Keyword.get(overrides, :revision, 1),
        supersedes_observation_id: Keyword.get(overrides, :supersedes_observation_id)
      )

    envelope
  end
end
