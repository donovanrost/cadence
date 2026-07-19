defmodule CadenceWeb.OpsDataSourcesLive.SourceActivityPresentation do
  @moduledoc """
  Deployment and source-activity row presentation with safe probe diagnostics.
  """

  @redacted_probe_keys [
    :access_key,
    :api_key,
    :api_token,
    :apikey,
    :bearer_token,
    :credential,
    :credentials,
    :password,
    :passwd,
    :secret,
    :secret_key,
    :token,
    "access_key",
    "api_key",
    "api_token",
    "apikey",
    "bearer_token",
    "credential",
    "credentials",
    "password",
    "passwd",
    "secret",
    "secret_key",
    "token"
  ]

  @spec deployment_run_row(map()) :: map()
  def deployment_run_row(run) do
    %{
      job_id: run.job_id,
      run_id: run.run_id,
      data_source_id: run.data_source_id,
      status_text: run.status_text,
      mode_text: run.mode_text,
      backend_text: run.backend_text,
      physical_boundary_text: run.physical_boundary_text,
      attempt_count_text: text(run.attempt_count),
      failure_summary: run.failure_summary,
      started_at_text: text(run.started_at),
      completed_at_text: text(run.completed_at),
      remediation: run.remediation
    }
  end

  @spec binding_event_row(map()) :: map()
  def binding_event_row(event) do
    %{
      id: "binding-event-#{event.data_binding_event_id}",
      event_type: text(event.event_type),
      title: "#{text(event.event_type)} #{event.binding_id}",
      subtitle:
        "#{text(event.current_logical_source)} / #{text(event.current_realm)} -> #{event.current_data_source_id}",
      occurred_at: text(event.occurred_at)
    }
  end

  @spec source_event_row(map()) :: map()
  def source_event_row(event) do
    %{
      id: "source-event-#{event.data_source_event_id}",
      event_type: text(event.event_type),
      title: "#{text(event.event_type)} #{event.data_source_id}",
      subtitle:
        "#{module_text(event.current_adapter)} / #{text(event.current_kind)} / #{text(event.current_isolation_level)}",
      occurred_at: text(event.occurred_at)
    }
  end

  @spec source_health_event_row(map()) :: map()
  def source_health_event_row(event) do
    %{
      id: "source-health-event-#{event.source_health_event_id}",
      event_type: text(event.event_type),
      title: "#{text(event.source_health)} #{text(event.logical_source)}",
      subtitle: "#{event.data_source_id} / #{text(event.realm)} / #{text(event.reason)}",
      occurred_at: text(event.observed_at),
      probe_kind: probe_payload_text(event, :probe_kind),
      probe_message: probe_payload_text(event, :probe_message),
      probe_metadata: probe_metadata_summary(event),
      probe_diagnostic_kind: probe_metadata_payload_text(event, :probe_diagnostic_kind),
      probe_diagnostic_stage: probe_metadata_payload_text(event, :probe_diagnostic_stage),
      probe_remediation: probe_metadata_payload_text(event, :probe_remediation),
      connection_test_result: probe_payload_text(event, :connection_test_result),
      connection_test_kind: probe_payload_text(event, :connection_test_kind),
      connection_test_message: probe_payload_text(event, :connection_test_message)
    }
  end

  @spec probe_payload_text(map() | nil, atom()) :: binary()
  def probe_payload_text(source_health, key) do
    source_health
    |> probe_payload_value(key)
    |> text()
  end

  @spec probe_metadata_payload_text(map() | nil, atom()) :: binary()
  def probe_metadata_payload_text(source_health, key) do
    source_health
    |> probe_payload_value(:probe_metadata)
    |> metadata_value(key)
    |> text()
  end

  @spec probe_metadata_summary(map() | nil) :: binary()
  def probe_metadata_summary(source_health) do
    case probe_payload_value(source_health, :probe_metadata) do
      metadata when is_map(metadata) and map_size(metadata) > 0 ->
        metadata
        |> Enum.map(fn {key, value} -> "#{key}=#{safe_probe_metadata_value(key, value)}" end)
        |> Enum.sort()
        |> Enum.join(" ")

      _other ->
        "none"
    end
  end

  @spec connection_profile(map() | nil) :: map() | nil
  def connection_profile(source_health) do
    source_health
    |> probe_payload_value(:probe_metadata)
    |> metadata_value(:source_connection_profile)
  end

  defp probe_payload_value(%{payload: payload}, key) when is_map(payload) do
    Map.get(payload, Atom.to_string(key), Map.get(payload, key))
  end

  defp probe_payload_value(_source_health, _key), do: nil

  defp safe_probe_metadata_value(key, _value) when key in @redacted_probe_keys, do: "redacted"
  defp safe_probe_metadata_value(_key, value) when is_boolean(value), do: to_string(value)
  defp safe_probe_metadata_value(_key, nil), do: "none"
  defp safe_probe_metadata_value(_key, value) when is_binary(value), do: value
  defp safe_probe_metadata_value(_key, value) when is_atom(value), do: Atom.to_string(value)
  defp safe_probe_metadata_value(_key, value) when is_number(value), do: to_string(value)
  defp safe_probe_metadata_value(_key, _value), do: "complex"

  defp metadata_value(metadata, key) when is_map(metadata) and is_atom(key) do
    Map.get(metadata, key, Map.get(metadata, Atom.to_string(key)))
  end

  defp metadata_value(_metadata, _key), do: nil

  defp module_text(nil), do: "none"

  defp module_text(module) when is_atom(module) do
    module
    |> Module.split()
    |> Enum.join(".")
  end

  defp module_text(value), do: text(value)

  defp text(nil), do: "none"
  defp text(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp text(value) when is_atom(value), do: Atom.to_string(value)
  defp text(value) when is_binary(value), do: value
  defp text(value), do: to_string(value)
end
