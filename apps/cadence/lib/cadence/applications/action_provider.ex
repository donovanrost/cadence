defmodule Cadence.Applications.ActionProvider do
  @moduledoc "First-party domain adapter contract behind the application action dispatcher."

  alias Cadence.Applications.{ActionFailure, ActionRequest, HostContext}
  alias Cadence.Auth.Scope

  @callback execute(Scope.t(), HostContext.t(), ActionRequest.t()) ::
              {:ok, term()} | {:error, ActionFailure.t() | term()}

  @callback application_key() :: binary()

  @callback result(term()) :: term()

  @optional_callbacks result: 1
end
