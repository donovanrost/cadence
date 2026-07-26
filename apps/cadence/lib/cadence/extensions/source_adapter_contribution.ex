defmodule Cadence.Extensions.SourceAdapterContribution do
  @moduledoc "A typed package contribution referencing one built-in dashboard source adapter."

  @type t :: %__MODULE__{
          logical_source: atom(),
          source_adapter_version: pos_integer()
        }

  @enforce_keys [:logical_source, :source_adapter_version]
  defstruct [:logical_source, :source_adapter_version]

  @spec validate(t()) :: :ok | {:error, :invalid_source_adapter_contribution}
  def validate(%__MODULE__{} = contribution) do
    if is_atom(contribution.logical_source) and not is_nil(contribution.logical_source) and
         is_integer(contribution.source_adapter_version) and
         contribution.source_adapter_version > 0 do
      :ok
    else
      {:error, :invalid_source_adapter_contribution}
    end
  end

  def validate(_contribution), do: {:error, :invalid_source_adapter_contribution}
end
