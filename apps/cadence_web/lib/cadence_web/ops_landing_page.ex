defmodule CadenceWeb.OpsLandingPage do
  @moduledoc "Fixed host-owned Ops entry; navigation reads remain authorized in Phoenix."

  alias Cadence.Auth.Scope
  alias Cadence.Reads.OpsWorkspace.Landing

  def load(%Scope{} = scope, %{
        route: "/missions/:mission_id/ops",
        params: %{"mission_id" => mission_id}
      }) do
    case Landing.load(scope, mission_id) do
      {:ok, model} -> model
      _ -> nil
    end
  rescue
    _ -> nil
  end

  def load(_, _), do: nil
end
