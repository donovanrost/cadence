defmodule Cadence.Dashboards.SourceCredentials.SecretBackend do
  @moduledoc """
  Behaviour for resolving dashboard source credential material from a secret store.

  Implementations receive the non-secret, scope-checked credential descriptor and
  return ephemeral adapter material. Returned values are validated by
  `SecretMaterialResolver` before they are handed to adapters.
  """

  alias Cadence.Dashboards.ResolvedSourceCredential

  @type material :: map()
  @type reason :: term()

  @callback fetch_material(ResolvedSourceCredential.t(), keyword()) ::
              {:ok, material()} | {:error, reason()}
end
