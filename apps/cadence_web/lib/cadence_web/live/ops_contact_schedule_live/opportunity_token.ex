defmodule CadenceWeb.OpsContactScheduleLive.OpportunityToken do
  @moduledoc false

  alias Cadence.ContactPlanning.OpportunityCapability

  @spec sign(map()) :: binary()
  def sign(payload), do: OpportunityCapability.sign(payload)

  @spec verify(binary(), keyword()) :: {:ok, map()} | {:error, term()}
  def verify(token, opts \\ []), do: OpportunityCapability.verify(token, opts)
end
