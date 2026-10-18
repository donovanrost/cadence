defmodule Cadence.Applications.TelemetryDecom.Review do
  @moduledoc "Scoped review references for desired spacecraft and mission decomposition configuration."

  alias Cadence.Applications.{ApplicationBindingStore, ConfigurationLock, PacketBindings}
  alias Cadence.Platform.ContentHash

  @maximum_rows 200

  @doc "Read under ConfigurationLock when combining this evidence with other configuration reads."
  def snapshot(organization_id, mission_id, spacecraft_id) do
    bindings =
      ApplicationBindingStore.list(organization_id, mission_id,
        application_key: "telemetry_decom"
      )

    packets =
      PacketBindings.list_for_mission(organization_id, mission_id,
        application_key: "telemetry_decom"
      )
      |> Enum.map(&canonical_packet_input/1)
      |> Enum.sort_by(& &1.packet_binding_configuration_id)

    local_bindings = Enum.filter(bindings, &(&1.spacecraft_id == spacecraft_id))
    local_packets = Enum.filter(packets, &(&1.spacecraft_id == spacecraft_id))
    total = length(bindings) + length(packets)
    truncated? = total > @maximum_rows

    %{
      "configuration_token" =>
        ContentHash.term_sha256(
          {1, organization_id, mission_id, spacecraft_id, local_bindings, local_packets}
        ),
      "mission_token" =>
        if(truncated?,
          do: nil,
          else: ContentHash.term_sha256({1, organization_id, mission_id, bindings, packets})
        ),
      "total_count" => total,
      "truncated" => truncated?,
      "configurations" => bindings |> Enum.take(@maximum_rows) |> Enum.map(&configuration/1),
      "packet_inputs" =>
        packets
        |> Enum.take(max(0, @maximum_rows - length(bindings)))
        |> Enum.map(&packet_input/1)
    }
  end

  def run(organization_id, mission_id, spacecraft_id, action_id, params, operation) do
    key = if action_id == "request_activation", do: "mission_token", else: "configuration_token"

    case Map.get(params, "expected_review", Map.get(params, :expected_review)) do
      token when is_binary(token) and byte_size(token) == 64 ->
        ConfigurationLock.run(organization_id, mission_id, fn ->
          evidence = snapshot(organization_id, mission_id, spacecraft_id)

          admit(evidence[key], token, operation)
        end)

      _ ->
        {:error, :telemetry_decom_review_required}
    end
  end

  defp admit(token, token, operation), do: operation.()
  defp admit(_current, _expected, _operation), do: {:error, :telemetry_decom_review_conflict}

  defp canonical_packet_input(configuration) do
    bindings =
      configuration.bindings
      |> Enum.map(fn binding ->
        %{binding | resources: Enum.sort_by(binding.resources, &{&1.resource_id, &1.path})}
      end)
      |> Enum.sort_by(& &1.packet_binding_id)

    %{configuration | bindings: bindings}
  end

  defp configuration(binding) do
    %{
      "spacecraft_id" => binding.spacecraft_id,
      "configuration_version" => binding.configuration_version,
      "catalog_revision_id" => binding.catalog_revision_id,
      "source_endpoint_id" => binding.source_endpoint_id,
      "handled_apids" => binding.handled_apids,
      "enabled" => binding.enabled
    }
  end

  defp packet_input(configuration) do
    %{
      "id" => configuration.packet_binding_configuration_id,
      "spacecraft_id" => configuration.spacecraft_id,
      "input_id" => configuration.input_id,
      "configuration_version" => configuration.configuration_version,
      "enabled" => configuration.enabled,
      "packet_count" => length(configuration.bindings)
    }
  end
end
