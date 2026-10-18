defmodule Cadence.TestHostQueryProviders.Collision do
  @moduledoc false

  @behaviour Cadence.Applications.HostQueryProvider

  @impl true
  def application_key, do: "synthetic_collision"

  @impl true
  def query_id, do: "synthetic.shared.read"

  @impl true
  def query(_scope, _route_context, _params, "synthetic.shared.read") do
    {:ok, %{"provider" => "collision"}}
  end
end
