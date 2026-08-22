defmodule Cadence.Reads.Applications.StatusProvider do
  @moduledoc "Read-side contract for a registered application status projection."

  alias Cadence.Applications.{HostContext, Status}
  alias Cadence.Auth.Scope

  @callback load(Scope.t(), HostContext.t()) :: {:ok, Status.t()} | {:error, term()}
end
