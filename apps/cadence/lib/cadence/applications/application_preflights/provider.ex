defmodule Cadence.Applications.ApplicationPreflights.Provider do
  @moduledoc "Domain-owned provider behind a registered activation-preflight query."

  alias Cadence.Applications.{ApplicationDefinition, HostContext, PreflightCheck}
  alias Cadence.Auth.Scope

  @callback checks(Scope.t(), HostContext.t(), ApplicationDefinition.t()) ::
              {:ok, [PreflightCheck.t()]} | {:error, term()}
end
