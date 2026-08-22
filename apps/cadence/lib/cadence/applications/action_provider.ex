defmodule Cadence.Applications.ActionProvider do
  @moduledoc "First-party domain adapter contract behind the application action dispatcher."

  alias Cadence.Applications.{ActionFailure, ActionRequest, ConfigurationReference, HostContext}
  alias Cadence.Auth.Scope

  @callback execute(Scope.t(), HostContext.t(), ActionRequest.t()) ::
              {:ok, term()} | {:error, ActionFailure.t() | term()}

  @callback configuration_reference(ActionRequest.t(), term()) ::
              ConfigurationReference.t() | nil

  @optional_callbacks configuration_reference: 2
end
