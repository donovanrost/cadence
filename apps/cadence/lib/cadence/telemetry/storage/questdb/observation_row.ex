defmodule Cadence.Telemetry.Storage.QuestDB.ObservationRow do
  @moduledoc """
  Serializes storage observation envelopes into QuestDB PGWire inserts.
  """

  alias Cadence.Telemetry.Storage.ObservationEnvelope
  alias Cadence.Telemetry.Storage.QuestDB.SQL

  @columns [
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

  @spec insert_sql(ObservationEnvelope.t()) :: binary()
  def insert_sql(%ObservationEnvelope{} = envelope) do
    column_sql =
      Enum.map_join(@columns, ", ", &Atom.to_string/1)

    value_sql =
      envelope
      |> params()
      |> Enum.map_join(", ", &SQL.literal/1)

    "INSERT INTO telemetry_observations (#{column_sql}) VALUES(#{value_sql})"
  end

  @spec params(ObservationEnvelope.t()) :: [term()]
  def params(%ObservationEnvelope{} = envelope) do
    {value_kind, value_double, value_long, value_bool, value_string} =
      typed_value(envelope.engineering_value)

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
      json(envelope.provenance),
      json(envelope.metadata)
    ]
  end

  @spec observed_at(ObservationEnvelope.t()) :: NaiveDateTime.t()
  def observed_at(%ObservationEnvelope{} = envelope) do
    envelope.generation_time
    |> Kernel.||(envelope.receipt_time)
    |> timestamp_param()
  end

  defp typed_value(value) when is_float(value), do: {"double", value, nil, nil, nil}
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
    |> normalize_json()
    |> Jason.encode!()
  end

  defp textual_value(value), do: inspect(value)

  defp json(value) do
    value
    |> normalize_json()
    |> Jason.encode!()
  end

  defp normalize_json(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp normalize_json(%NaiveDateTime{} = datetime), do: NaiveDateTime.to_iso8601(datetime)
  defp normalize_json(%Date{} = date), do: Date.to_iso8601(date)
  defp normalize_json(%Time{} = time), do: Time.to_iso8601(time)
  defp normalize_json(nil), do: nil
  defp normalize_json(atom) when is_atom(atom), do: Atom.to_string(atom)

  defp normalize_json(%{} = map) do
    Map.new(map, fn {key, value} ->
      {normalize_json_key(key), normalize_json(value)}
    end)
  end

  defp normalize_json(list) when is_list(list), do: Enum.map(list, &normalize_json/1)

  defp normalize_json(tuple) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> normalize_json()

  defp normalize_json(value) when is_binary(value) or is_number(value) or is_boolean(value),
    do: value

  defp normalize_json(value), do: inspect(value)

  defp normalize_json_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_json_key(key) when is_binary(key), do: key
  defp normalize_json_key(key), do: to_string(key)
end
