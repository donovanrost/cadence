defmodule CadenceWeb.OpsContactScheduleLive.OpportunityToken do
  @moduledoc false

  @salt "ops-contact-opportunity-v1"
  @default_max_age 15 * 60

  @spec sign(map()) :: binary()
  def sign(payload) when is_map(payload) do
    Phoenix.Token.sign(CadenceWeb.Endpoint, @salt, payload)
  end

  @spec verify(binary(), keyword()) :: {:ok, map()} | {:error, term()}
  def verify(token, opts \\ []) when is_binary(token) do
    Phoenix.Token.verify(
      CadenceWeb.Endpoint,
      @salt,
      token,
      max_age: Keyword.get(opts, :max_age, @default_max_age)
    )
  end
end
