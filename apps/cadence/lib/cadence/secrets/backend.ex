defmodule Cadence.Secrets.Backend do
  @moduledoc "Capability-based contract for ephemeral secret backends."

  @type capability :: :resolve | :create | :rotate | :revoke
  @type descriptor :: struct() | map()
  @type response :: map() | binary()

  @callback capabilities(keyword()) :: [capability()]
  @callback resolve(descriptor(), keyword()) :: {:ok, response()} | {:error, term()}
  @callback create(descriptor(), keyword()) :: {:ok, response()} | {:error, term()}
  @callback rotate(descriptor(), keyword()) :: {:ok, response()} | {:error, term()}
  @callback revoke(descriptor(), keyword()) :: {:ok, response()} | {:error, term()}

  @optional_callbacks create: 2, rotate: 2, revoke: 2
end
