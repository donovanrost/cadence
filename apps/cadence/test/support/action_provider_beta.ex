defmodule Cadence.TestActionProviders.Beta do
  @moduledoc false

  @behaviour Cadence.Applications.ActionProvider

  @impl true
  def application_key, do: "synthetic_beta"

  @impl true
  def execute(_scope, host_context, _request) do
    {:ok, %{"provider" => "beta", "missionId" => host_context.mission_id}}
  end
end
