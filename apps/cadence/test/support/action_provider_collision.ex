defmodule Cadence.TestActionProviders.Collision do
  @moduledoc false

  @behaviour Cadence.Applications.ActionProvider

  @impl true
  def application_key, do: "synthetic_alpha"

  @impl true
  def execute(_scope, _host_context, _request), do: {:ok, %{"provider" => "collision"}}
end
