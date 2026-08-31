defmodule Cadence.TestActionProviders.Alpha do
  @moduledoc false

  @behaviour Cadence.Applications.ActionProvider

  @impl true
  def application_key, do: "synthetic_alpha"

  @impl true
  def execute(_scope, host_context, _request) do
    {:ok, %{"provider" => "alpha", "missionId" => host_context.mission_id}}
  end
end
