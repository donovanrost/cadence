defmodule Cadence.TestHostQueryProviders.DuplicateApplication do
  @moduledoc false

  @behaviour Cadence.Applications.HostQueryProvider

  @impl true
  def application_key, do: "synthetic_alpha"

  @impl true
  def query_id, do: "synthetic.alpha.other"

  @impl true
  def query(_scope, _route_context, _params, "synthetic.alpha.other"),
    do: {:ok, %{"provider" => "duplicate-application"}}
end
