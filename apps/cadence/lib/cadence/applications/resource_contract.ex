defmodule Cadence.Applications.ResourceContract do
  @moduledoc "Typed resource declarations contributed by one product application."

  alias Cadence.Applications.ResourceClaimDefinition

  @type t :: %__MODULE__{claims: [ResourceClaimDefinition.t()]}

  defstruct claims: []

  @max_claims 32

  @spec validate(t()) :: :ok | {:error, :invalid_application_resource_contract}
  def validate(%__MODULE__{claims: claims}) when is_list(claims) do
    identities = Enum.map(claims, &claim_identity/1)

    if length(claims) <= @max_claims and
         Enum.all?(claims, &(ResourceClaimDefinition.validate(&1) == :ok)) and
         length(Enum.uniq(identities)) == length(identities) do
      :ok
    else
      {:error, :invalid_application_resource_contract}
    end
  end

  def validate(_contract), do: {:error, :invalid_application_resource_contract}

  defp claim_identity(%ResourceClaimDefinition{claim_type: claim_type, scope: scope}),
    do: {claim_type, scope}

  defp claim_identity(_claim), do: nil
end
