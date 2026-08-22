defmodule Cadence.Extensions.TransportKindContribution do
  @moduledoc "A typed package contribution referencing one transport-kind definition version."

  @type t :: %__MODULE__{
          transport_kind_key: binary(),
          transport_kind_version: pos_integer()
        }

  @enforce_keys [:transport_kind_key, :transport_kind_version]
  defstruct [:transport_kind_key, :transport_kind_version]

  @spec validate(t()) :: :ok | {:error, :invalid_transport_kind_contribution}
  def validate(%__MODULE__{} = contribution) do
    if is_binary(contribution.transport_kind_key) and contribution.transport_kind_key != "" and
         is_integer(contribution.transport_kind_version) and
         contribution.transport_kind_version > 0 do
      :ok
    else
      {:error, :invalid_transport_kind_contribution}
    end
  end

  def validate(_contribution), do: {:error, :invalid_transport_kind_contribution}
end
