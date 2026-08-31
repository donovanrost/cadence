defmodule Cadence.TestHostQueryProviders.InvalidOutput do
  @moduledoc false

  @behaviour Cadence.Applications.HostQueryProvider

  @impl true
  def application_key, do: "synthetic_invalid_output"

  @impl true
  def query_id, do: "synthetic.invalid.output"

  @impl true
  def query(_scope, _route_context, _params, "synthetic.invalid.output"),
    do: {:ok, %{"provider" => self()}}
end
