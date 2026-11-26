defmodule Cadence.Telemetry.Storage.QuestDB.ObservationRow do
  @moduledoc """
  Serializes storage observation envelopes into QuestDB PGWire inserts.
  """

  alias Cadence.Telemetry.Storage.ObservationEnvelope
  alias Cadence.Telemetry.Storage.QuestDB.{ObservationProvenance, SQL}

  @base_columns [
    :observed_at,
    :generation_time,
    :receipt_time,
    :ingested_at,
    :organization_id,
    :mission_id,
    :realm,
    :data_source_id,
    :binding_id,
    :source_endpoint_id,
    :replay_run_id,
    :observation_id,
    :observation_identity_id,
    :idempotency_key,
    :sample_id,
    :spacecraft_id,
    :observable_id,
    :point_id,
    :point_name,
    :packet_definition_id,
    :packet_definition_version,
    :packet_id,
    :evidence_id,
    :value_kind,
    :value_double,
    :value_long,
    :value_bool,
    :value_string,
    :raw_value_text,
    :quality_state,
    :validity_state,
    :revision,
    :supersedes_observation_id,
    :provenance_json,
    :metadata_json
  ]

  # The provenance columns (DECISIONS #103) follow the base columns; `provenance_json` holds only
  # the residual that has no column.
  @columns @base_columns ++ ObservationProvenance.columns()

  @spec columns() :: [atom()]
  def columns, do: @columns

  @spec insert_statement() :: binary()
  def insert_statement do
    column_sql =
      Enum.map_join(@columns, ", ", &Atom.to_string/1)

    value_sql =
      Enum.map_join(1..length(@columns), ", ", &"$#{&1}")

    "INSERT INTO telemetry_observations (#{column_sql}) VALUES(#{value_sql})"
  end

  @spec insert_sql(ObservationEnvelope.t() | [ObservationEnvelope.t()]) :: binary()
  def insert_sql(%ObservationEnvelope{} = envelope), do: insert_sql([envelope])

  def insert_sql([%ObservationEnvelope{} | _] = envelopes) do
    column_sql =
      Enum.map_join(@columns, ", ", &Atom.to_string/1)

    value_sql =
      Enum.map_join(envelopes, ", ", fn envelope ->
        "(" <> Enum.map_join(params(envelope), ", ", &SQL.literal/1) <> ")"
      end)

    "INSERT INTO telemetry_observations (#{column_sql}) VALUES#{value_sql}"
  end

  @spec params(ObservationEnvelope.t()) :: [term()]
  def params(%ObservationEnvelope{} = envelope) do
    {value_kind, value_double, value_long, value_bool, value_string} =
      typed_value(envelope.engineering_value)

    {provenance_values, residual_provenance_json} = ObservationProvenance.params(envelope)

    [
      observed_at(envelope),
      timestamp_param(envelope.generation_time),
      timestamp_param(envelope.receipt_time),
      timestamp_param(envelope.ingested_at),
      envelope.organization_id,
      envelope.mission_id,
      Atom.to_string(envelope.realm),
      envelope.data_source_id,
      envelope.binding_id,
      envelope.source_endpoint_id,
      envelope.replay_run_id,
      envelope.observation_id,
      envelope.observation_identity_id,
      envelope.idempotency_key,
      envelope.sample_id,
      envelope.spacecraft_id,
      envelope.observable_id,
      envelope.point_id,
      envelope.point_name,
      envelope.packet_definition_id,
      envelope.packet_definition_version,
      envelope.packet_id,
      envelope.evidence_id,
      value_kind,
      value_double,
      value_long,
      value_bool,
      value_string,
      textual_value(envelope.raw_value),
      Atom.to_string(envelope.quality_state),
      Atom.to_string(envelope.validity_state),
      envelope.revision,
      envelope.supersedes_observation_id,
      residual_provenance_json,
      json(envelope.metadata)
      | provenance_values
    ]
  end

  @spec observed_at(ObservationEnvelope.t()) :: NaiveDateTime.t()
  def observed_at(%ObservationEnvelope{} = envelope) do
    envelope.generation_time
    |> Kernel.||(envelope.receipt_time)
    |> timestamp_param()
  end

  defp typed_value(value) when is_float(value), do: {"double", value, nil, nil, nil}

  # QuestDB LONG is signed and reserves its minimum value for NULL. Preserve
  # wider spacecraft counters losslessly through the existing JSON term path.
  defp typed_value(value)
       when is_integer(value) and
              (value <= -9_223_372_036_854_775_808 or value > 9_223_372_036_854_775_807),
       do: {"term", nil, nil, nil, Integer.to_string(value)}

  defp typed_value(value) when is_integer(value), do: {"long", nil, value, nil, nil}
  defp typed_value(value) when is_boolean(value), do: {"bool", nil, nil, value, nil}
  defp typed_value(value) when is_binary(value), do: {"string", nil, nil, nil, value}
  defp typed_value(nil), do: {"nil", nil, nil, nil, nil}
  defp typed_value(value), do: {"term", nil, nil, nil, textual_value(value)}

  defp timestamp_param(nil), do: nil

  defp timestamp_param(%DateTime{} = datetime) do
    datetime
    |> DateTime.shift_zone!("Etc/UTC")
    |> DateTime.to_naive()
  end

  defp textual_value(nil), do: nil
  defp textual_value(value) when is_binary(value), do: value
  defp textual_value(value) when is_number(value), do: to_string(value)
  defp textual_value(value) when is_boolean(value), do: to_string(value)

  defp textual_value(value) when is_map(value) or is_list(value) do
    value
    |> ObservationProvenance.json_term()
    |> Jason.encode!()
  end

  defp textual_value(value), do: inspect(value)

  defp json(value) do
    value
    |> ObservationProvenance.json_term()
    |> Jason.encode!()
  end
end
