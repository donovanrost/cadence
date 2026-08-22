defmodule Cadence.Extensions.ApplicationContribution do
  @moduledoc "A typed package contribution referencing one product application version."

  @type t :: %__MODULE__{application_key: binary(), application_version: pos_integer()}

  @enforce_keys [:application_key, :application_version]
  defstruct [:application_key, :application_version]

  @spec validate(t()) :: :ok | {:error, :invalid_application_contribution}
  def validate(%__MODULE__{} = contribution) do
    if is_binary(contribution.application_key) and contribution.application_key != "" and
         is_integer(contribution.application_version) and contribution.application_version > 0 do
      :ok
    else
      {:error, :invalid_application_contribution}
    end
  end

  def validate(_contribution), do: {:error, :invalid_application_contribution}
end
