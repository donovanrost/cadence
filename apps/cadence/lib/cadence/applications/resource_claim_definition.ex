defmodule Cadence.Applications.ResourceClaimDefinition do
  @moduledoc """
  Compiled declaration of a resource family used by a product application.

  The declaration is presentation and preflight metadata. Resource identity,
  conflict detection, persistence, and activation remain in the owning domain.
  """

  @type claim_mode :: :exclusive | :shared | :reference
  @type scope :: :mission | :spacecraft | :source_endpoint | :transport

  @type t :: %__MODULE__{
          claim_type: atom(),
          scope: scope(),
          mode: claim_mode(),
          required: boolean(),
          description: binary()
        }

  @enforce_keys [:claim_type, :scope, :mode, :description]
  defstruct [:claim_type, :scope, :mode, :description, required: true]

  @spec validate(t()) :: :ok | {:error, :invalid_application_resource_claim}
  def validate(%__MODULE__{} = claim) do
    if is_atom(claim.claim_type) and not is_nil(claim.claim_type) and
         claim.scope in [:mission, :spacecraft, :source_endpoint, :transport] and
         claim.mode in [:exclusive, :shared, :reference] and is_boolean(claim.required) and
         valid_text?(claim.description) do
      :ok
    else
      {:error, :invalid_application_resource_claim}
    end
  end

  def validate(_claim), do: {:error, :invalid_application_resource_claim}

  defp valid_text?(value), do: is_binary(value) and value != ""
end
