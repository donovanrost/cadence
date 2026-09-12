defmodule Cadence.Reads.Comms.SpacecraftReadiness do
  @moduledoc "Comms-owned routing setup status; not a runtime connectivity or commanding approval."
  @behaviour Cadence.Reads.Applications.StatusProvider
  alias Cadence.Applications.{HostContext, Status}
  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Comms.RoutingRuleStore
  alias Cadence.SpacecraftStore
  @impl true
  def load(
        %Scope{mission_id: scoped} = scope,
        %HostContext{placement: :spacecraft, mission_id: mission_id, spacecraft_id: id}
      )
      when is_nil(scoped) or scoped == mission_id do
    with :ok <-
           Policy.authorize(scope, :operate_mission, %{
             organization_id: scope.organization_id,
             mission_id: mission_id
           }),
         {:ok, _} <- SpacecraftStore.fetch_spacecraft(scope.organization_id, mission_id, id) do
      rules =
        RoutingRuleStore.list_routing_rules_for_spacecraft(scope.organization_id, mission_id, id)

      enabled = Enum.count(rules, & &1.enabled?)

      {:ok,
       %Status{
         state: :routing_setup,
         tone: :info,
         label: "Review routing",
         facts: [
           %{id: "enabled", label: "Enabled routing rules", value: to_string(enabled)},
           %{
             id: "boundary",
             label: "Scope",
             value: "Setup only; runtime connectivity is not assessed."
           }
         ]
       }}
    end
  end

  def load(_scope, _context), do: {:error, :unsupported_readiness_context}
end
