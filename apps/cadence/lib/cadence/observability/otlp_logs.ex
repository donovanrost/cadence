defmodule Cadence.Observability.OtlpLogs do
  @moduledoc false

  @protobuf_module :opentelemetry_exporter_logs_service_pb
  @scope_name "cadence.logger"
  @default_body_limit 16_384

  @metadata_attributes %{
    cadence_event: "event.name",
    error_class: "error.type",
    mission_id: "cadence.mission.id",
    path_id: "cadence.path.id",
    provider_binding_id: "cadence.provider.binding.id",
    realized_contact_id: "cadence.contact.id",
    request_id: "http.request.id",
    source_endpoint_id: "cadence.source_endpoint.id",
    spacecraft_id: "cadence.spacecraft.id"
  }

  @spec encode([map()], keyword()) :: binary()
  def encode(events, opts \\ []) when is_list(events) do
    body_limit = Keyword.get(opts, :body_limit, @default_body_limit)

    request = %{
      resource_logs: [
        %{
          resource: %{attributes: resource_attributes()},
          scope_logs: [
            %{
              scope: %{
                name: @scope_name,
                version: Application.spec(:cadence, :vsn) |> to_string()
              },
              log_records: Enum.map(events, &log_record(&1, body_limit))
            }
          ]
        }
      ]
    }

    @protobuf_module.encode_msg(request, :export_logs_service_request)
  end

  @spec decode_response(binary()) :: :ok | {:error, term()}
  def decode_response(<<>>), do: :ok

  def decode_response(body) when is_binary(body) do
    case @protobuf_module.decode_msg(body, :export_logs_service_response) do
      %{partial_success: %{rejected_log_records: rejected}} when rejected > 0 ->
        {:error, {:partial_success, rejected}}

      _response ->
        :ok
    end
  rescue
    _exception -> {:error, :invalid_response}
  end

  defp log_record(%{level: level, msg: _message, meta: metadata} = event, body_limit)
       when is_map(metadata) do
    %{
      time_unix_nano: event_timestamp(metadata),
      observed_time_unix_nano: System.system_time(:nanosecond),
      severity_number: severity_number(level),
      severity_text: level |> to_string() |> String.upcase(),
      body: any_value(Logger.Formatter.format_event(event, body_limit)),
      attributes: log_attributes(metadata),
      flags: trace_flags(metadata)
    }
    |> maybe_put_binary(:trace_id, metadata[:otel_trace_id], 16)
    |> maybe_put_binary(:span_id, metadata[:otel_span_id], 8)
  end

  defp event_timestamp(%{time: timestamp}) when is_integer(timestamp), do: timestamp * 1_000
  defp event_timestamp(_metadata), do: System.system_time(:nanosecond)

  defp severity_number(:debug), do: :SEVERITY_NUMBER_DEBUG
  defp severity_number(:info), do: :SEVERITY_NUMBER_INFO
  defp severity_number(:notice), do: :SEVERITY_NUMBER_INFO2
  defp severity_number(:warning), do: :SEVERITY_NUMBER_WARN
  defp severity_number(:error), do: :SEVERITY_NUMBER_ERROR
  defp severity_number(:critical), do: :SEVERITY_NUMBER_FATAL
  defp severity_number(:alert), do: :SEVERITY_NUMBER_FATAL2
  defp severity_number(:emergency), do: :SEVERITY_NUMBER_FATAL3
  defp severity_number(_level), do: :SEVERITY_NUMBER_UNSPECIFIED

  defp trace_flags(%{otel_trace_flags: flags}) when is_binary(flags) do
    case Integer.parse(flags, 16) do
      {value, ""} -> value
      _invalid -> 0
    end
  end

  defp trace_flags(_metadata), do: 0

  defp maybe_put_binary(record, key, encoded, expected_size) when is_binary(encoded) do
    case Base.decode16(encoded, case: :mixed) do
      {:ok, value} when byte_size(value) == expected_size -> Map.put(record, key, value)
      _invalid -> record
    end
  end

  defp maybe_put_binary(record, _key, _encoded, _expected_size), do: record

  defp log_attributes(metadata) do
    domain_attributes =
      @metadata_attributes
      |> Enum.flat_map(fn {metadata_key, attribute_key} ->
        case Map.get(metadata, metadata_key) do
          nil -> []
          "" -> []
          value -> [key_value(attribute_key, value)]
        end
      end)

    domain_attributes ++ code_attributes(metadata)
  end

  defp code_attributes(metadata) do
    []
    |> maybe_add_attribute("code.file.path", metadata[:file])
    |> maybe_add_attribute("code.line.number", metadata[:line])
    |> add_mfa_attributes(metadata[:mfa])
  end

  defp add_mfa_attributes(attributes, {module, function, arity})
       when is_atom(module) and is_atom(function) and is_integer(arity) do
    attributes
    |> maybe_add_attribute("code.namespace", inspect(module))
    |> maybe_add_attribute("code.function.name", "#{function}/#{arity}")
  end

  defp add_mfa_attributes(attributes, _mfa), do: attributes

  defp maybe_add_attribute(attributes, _key, nil), do: attributes

  defp maybe_add_attribute(attributes, key, value) do
    [key_value(key, value) | attributes]
  end

  defp resource_attributes do
    :otel_resource_detector.get_resource()
    |> :otel_resource.attributes()
    |> :otel_attributes.map()
    |> Enum.map(fn {key, value} -> key_value(to_string(key), value) end)
  end

  defp key_value(key, value), do: %{key: key, value: any_value(value)}

  defp any_value(value) when is_boolean(value), do: %{value: {:bool_value, value}}

  defp any_value(value)
       when is_integer(value) and value >= -9_223_372_036_854_775_808 and
              value <= 9_223_372_036_854_775_807,
       do: %{value: {:int_value, value}}

  defp any_value(value) when is_integer(value),
    do: %{value: {:string_value, Integer.to_string(value)}}

  defp any_value(value) when is_float(value), do: %{value: {:double_value, value}}
  defp any_value(value) when is_binary(value), do: %{value: {:string_value, value}}
  defp any_value(value) when is_atom(value), do: %{value: {:string_value, Atom.to_string(value)}}

  defp any_value(value) when is_list(value) do
    case :unicode.characters_to_binary(value) do
      binary when is_binary(binary) -> %{value: {:string_value, binary}}
      _invalid -> %{value: {:string_value, inspect(value, limit: 20)}}
    end
  end

  defp any_value(value), do: %{value: {:string_value, inspect(value, limit: 20)}}
end
