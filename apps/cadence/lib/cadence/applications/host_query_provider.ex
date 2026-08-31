defmodule Cadence.Applications.HostQueryProvider do
  @moduledoc "Application-owned compatibility query contract for host dispatch."

  alias Cadence.Auth.Scope

  @callback application_key() :: binary()
  @callback query_id() :: binary()
  @callback query(Scope.t(), map(), map(), binary()) :: {:ok, map()} | {:error, term()}
end
