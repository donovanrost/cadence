defmodule Cadence.TestHostQueryProviders.Beta do
  @moduledoc false

  @behaviour Cadence.Applications.HostQueryProvider

  @impl true
  def application_key, do: "synthetic_beta"

  @impl true
  def query_id, do: "synthetic.beta.read"

  @impl true
  def query(_scope, _route_context, params, "synthetic.beta.read") do
    {:ok, %{"provider" => "beta", "applicationKey" => Map.get(params, "applicationKey")}}
  end
end
