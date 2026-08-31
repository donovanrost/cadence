defmodule Cadence.TestSurfaceQueryProviders.Alpha do
  @moduledoc false

  @behaviour Cadence.Reads.ApplicationSurfaces.SurfaceQueryProvider

  @impl true
  def application_key, do: "synthetic_alpha"

  @impl true
  def load(_scope, _host_context, request) do
    {:ok, %{"provider" => "alpha", "application_key" => request.application_key}}
  end
end
