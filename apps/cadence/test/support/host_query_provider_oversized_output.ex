defmodule Cadence.TestHostQueryProviders.OversizedOutput do
  @moduledoc false

  @behaviour Cadence.Applications.HostQueryProvider

  @impl true
  def application_key, do: "synthetic_oversized_output"

  @impl true
  def query_id, do: "synthetic.oversized.output"

  @impl true
  def query(_scope, _route_context, _params, "synthetic.oversized.output"),
    do: {:ok, %{"items" => Enum.to_list(1..101)}}
end
