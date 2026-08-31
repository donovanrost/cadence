defmodule Cadence.TestHostQueryProviders.Alpha do
  @moduledoc false

  @behaviour Cadence.Applications.HostQueryProvider

  @impl true
  def application_key, do: "synthetic_alpha"

  @impl true
  def query_id, do: "synthetic.shared.read"

  @impl true
  def query(_scope, _route_context, params, "synthetic.shared.read") do
    {:ok, %{"provider" => "alpha", "applicationKey" => Map.get(params, "applicationKey")}}
  end
end
