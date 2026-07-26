defmodule Cadence.Extensions.CapabilityContribution do
  @moduledoc "A typed package contribution referencing one runtime capability family version."

  alias Cadence.Capabilities.Descriptor

  @type t :: %__MODULE__{
          family_key: atom(),
          family_version: pos_integer(),
          kind: Descriptor.kind()
        }

  @enforce_keys [:family_key, :family_version, :kind]
  defstruct [:family_key, :family_version, :kind]

  @spec validate(t()) :: :ok | {:error, :invalid_capability_contribution}
  def validate(%__MODULE__{} = contribution) do
    if is_atom(contribution.family_key) and not is_nil(contribution.family_key) and
         is_integer(contribution.family_version) and contribution.family_version > 0 and
         contribution.kind in [
           :semantic_handler,
           :managed_application,
           :projection,
           :transport_extension
         ] do
      :ok
    else
      {:error, :invalid_capability_contribution}
    end
  end

  def validate(_contribution), do: {:error, :invalid_capability_contribution}
end
