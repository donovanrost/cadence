defmodule Cadence.Extensions.ProviderConnectorContribution do
  @moduledoc "A typed package contribution referencing one provider-connector definition version."

  @type t :: %__MODULE__{
          provider_connector_key: binary(),
          provider_connector_version: pos_integer()
        }

  @enforce_keys [:provider_connector_key, :provider_connector_version]
  defstruct [:provider_connector_key, :provider_connector_version]

  @spec validate(t()) :: :ok | {:error, :invalid_provider_connector_contribution}
  def validate(%__MODULE__{} = contribution) do
    if is_binary(contribution.provider_connector_key) and
         contribution.provider_connector_key != "" and
         is_integer(contribution.provider_connector_version) and
         contribution.provider_connector_version > 0 do
      :ok
    else
      {:error, :invalid_provider_connector_contribution}
    end
  end

  def validate(_contribution), do: {:error, :invalid_provider_connector_contribution}
end
