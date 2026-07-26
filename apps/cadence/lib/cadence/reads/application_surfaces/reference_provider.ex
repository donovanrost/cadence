defmodule Cadence.Reads.ApplicationSurfaces.ReferenceProvider do
  @moduledoc "Contract implemented by registered host reference-data providers."

  alias Cadence.Applications.HostContext
  alias Cadence.Auth.Scope
  alias Cadence.Extensions.Presentation.{ReferenceDefinition, ReferencePage}

  @callback search(
              Scope.t(),
              HostContext.t(),
              ReferenceDefinition.t(),
              binary(),
              pos_integer()
            ) :: {:ok, ReferencePage.t()} | {:error, term()}
end
