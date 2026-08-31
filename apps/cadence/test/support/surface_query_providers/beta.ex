defmodule Cadence.TestSurfaceQueryProviders.Beta do
  @moduledoc false

  @behaviour Cadence.Reads.ApplicationSurfaces.SurfaceQueryProvider

  @impl true
  def application_key, do: "synthetic_beta"

  @impl true
  def load(_scope, _host_context, request) do
    {:ok, %{"provider" => "beta", "application_key" => request.application_key}}
  end
end
