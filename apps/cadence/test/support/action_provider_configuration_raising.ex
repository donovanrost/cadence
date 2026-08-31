defmodule Cadence.TestActionProviders.ConfigurationRaising do
  @moduledoc false

  @behaviour Cadence.Applications.ActionProvider

  @impl true
  def application_key, do: "derived_telemetry"

  @impl true
  def execute(_scope, _host_context, _request), do: {:ok, %{}}

  @impl true
  def configuration_reference(_request, _result),
    do: raise("synthetic configuration reference failure")
end
