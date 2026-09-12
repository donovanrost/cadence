defmodule Cadence.Reads.Dashboards.ExplorationSampleSnapshot do
  @moduledoc "Allowlisted browser projection of one authorized physical sample."
  alias Cadence.Reads.Dashboards.ExplorationSampleValue
  alias Cadence.Telemetry.Sample

  @realms ~w(flight rehearsal replay simulation)
  @qualities ~w(good suspect bad)
  @validity ~w(canonical duplicate conflict superseded advisory)

  def build(_result, %{} = query, _request) when not is_map_key(query, "sample_id"),
    do: empty("not_selected")

  def build({:ok, %Sample{} = sample}, query, request) do
    with true <- sample.mission_id == request.mission_id,
         true <- sample.point_id == query["point_id"] and sample.sample_id == query["sample_id"],
         true <- Enum.all?([sample.point_id, sample.sample_id], &identity?/1),
         true <-
           Enum.all?(
             [
               sample.point_name,
               sample.spacecraft_id,
               sample.packet_id,
               sample.evidence_id,
               sample.packet_definition_id
             ],
             &optional_identity?/1
           ),
         true <-
           is_nil(sample.packet_definition_version) or
             (is_integer(sample.packet_definition_version) and
                sample.packet_definition_version in 1..9_007_199_254_740_991),
         {:ok, receipt} <- timestamp(sample.receipt_time),
         true <- not is_nil(receipt),
         {:ok, generation} <- timestamp(sample.generation_time),
         true <- selected_time?(query["selected_time"], sample.receipt_time),
         quality = to_string(sample.quality_state),
         true <- quality in @qualities,
         {:ok, source, validity} <- source(sample.provenance),
         true <- query_context?(query, sample, source) do
      %{
        status: "ready",
        sample: %{
          point_id: sample.point_id,
          point_name: sample.point_name,
          sample_id: sample.sample_id,
          spacecraft_id: sample.spacecraft_id,
          receipt_time: receipt,
          generation_time: generation,
          quality: quality,
          raw_value: ExplorationSampleValue.project(sample.raw_value),
          engineering_value: ExplorationSampleValue.project(sample.engineering_value),
          source: source,
          record: %{
            packet_id: sample.packet_id,
            evidence_id: sample.evidence_id,
            packet_definition_id: sample.packet_definition_id,
            packet_definition_version: sample.packet_definition_version,
            validity_state: validity
          }
        }
      }
    else
      _ -> empty("unavailable")
    end
  rescue
    _ -> empty("unavailable")
  end

  def build({:error, :not_found}, _query, _request), do: empty("not_found")
  def build({:error, :ambiguous_physical_sample}, _query, _request), do: empty("ambiguous")
  def build({:error, :physical_sample_timeout}, _query, _request), do: empty("timeout")

  def build({:error, reason}, _query, _request)
      when reason in [
             :unsupported_sample_inspection,
             :unsupported_physical_sample_scope,
             :unsupported_physical_sample_time
           ],
      do: empty("unsupported")

  def build(_result, _query, _request), do: empty("unavailable")

  defp source(provenance) do
    storage = value(provenance, :storage)

    source = %{
      realm: to_string(value(storage, :realm)),
      data_source_id: value(storage, :data_source_id),
      source_binding_id: value(storage, :binding_id) || value(storage, :source_binding_id),
      source_endpoint_id: value(storage, :source_endpoint_id),
      replay_run_id: value(storage, :replay_run_id)
    }

    validity = value(storage, :validity_state)
    validity = if is_nil(validity), do: nil, else: to_string(validity)

    if valid_source?(source) and
         validity in [nil | @validity], do: {:ok, source, validity}, else: :error
  end

  defp valid_source?(source) do
    source.realm in @realms and
      Enum.all?([source.data_source_id, source.source_binding_id], &identity?/1) and
      Enum.all?([source.source_endpoint_id, source.replay_run_id], &optional_identity?/1) and
      source.realm == "replay" == not is_nil(source.replay_run_id)
  end

  defp timestamp(nil), do: {:ok, nil}

  defp timestamp(%DateTime{calendar: Calendar.ISO} = time) do
    value = DateTime.to_iso8601(time)

    with {:ok, parsed, _} <- DateTime.from_iso8601(value),
         true <- DateTime.compare(parsed, time) == :eq,
         do: {:ok, value}
  end

  defp timestamp(_), do: :error
  defp selected_time?(nil, _receipt), do: true

  defp selected_time?(value, receipt) do
    case DateTime.from_iso8601(value) do
      {:ok, selected, _} -> DateTime.compare(selected, receipt) == :eq
      _ -> false
    end
  end

  defp query_context?(query, sample, source) do
    expected_realm =
      query["realm"] || if(query["time_mode"] == "replay_run", do: "replay", else: "flight")

    selectors = [
      {"data_source_id", source.data_source_id},
      {"source_binding_id", source.source_binding_id},
      {"selected_data_source_id", source.data_source_id},
      {"selected_source_binding_id", source.source_binding_id},
      {"spacecraft_id", sample.spacecraft_id}
    ]

    source.realm == expected_realm and source.replay_run_id == query["replay_run_id"] and
      Enum.all?(selectors, fn {key, actual} -> is_nil(query[key]) or query[key] == actual end) and
      scope_matches?(query, sample, source)
  end

  defp scope_matches?(%{"scope_kind" => "source_endpoint", "scope_id" => id}, _sample, source),
    do: id == source.source_endpoint_id

  defp scope_matches?(%{"scope_kind" => "spacecraft", "scope_id" => id}, sample, _source),
    do: id == sample.spacecraft_id

  defp scope_matches?(_query, _sample, _source), do: true
  defp value(map, key) when is_map(map), do: Map.get(map, Atom.to_string(key), Map.get(map, key))
  defp value(_, _), do: nil
  defp optional_identity?(nil), do: true
  defp optional_identity?(value), do: identity?(value)

  defp identity?(value),
    do: is_binary(value) and byte_size(value) in 1..256 and String.valid?(value)

  defp empty(status), do: %{status: status, sample: nil}
end
