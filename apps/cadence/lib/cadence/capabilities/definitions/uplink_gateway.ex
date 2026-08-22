defmodule Cadence.Capabilities.Definitions.UplinkGateway do
  @moduledoc false

  alias Cadence.Capabilities.{Descriptor, ValidationContext}
  alias Cadence.Capabilities.TransportExtensions.UplinkGateway.Configuration

  @spec descriptor() :: Descriptor.t()
  def descriptor do
    Descriptor.new(%{
      family_key: :uplink_gateway,
      version: 1,
      kind: :transport_extension,
      supported_scopes: [:path, :transport],
      input_stages: [],
      partition_affinity: :path,
      config_schema: nil,
      emitted_record_kinds: [],
      emitted_action_kinds: [:uplink_request, :provider_request, :schedule_timer, :cancel_timer],
      replay_mode: :deterministic,
      state_mode: :stateful
    })
  end

  @spec validate_config(term(), ValidationContext.t()) :: :ok | {:error, term()}
  def validate_config(configuration, %ValidationContext{}) do
    with {:ok, normalized_configuration} <- Configuration.normalize(configuration) do
      Configuration.validate(normalized_configuration)
    end
  end
end
