defmodule Cadence.Reads.Applications.LimitsStatus do
  @moduledoc "Host-standard mission status for Limits and Alarming."

  @behaviour Cadence.Reads.Applications.StatusProvider

  alias Cadence.Applications.{HostContext, Status}
  alias Cadence.Auth.Scope
  alias Cadence.Limits
  alias Cadence.Reads.Limits, as: LimitReads

  @impl true
  def load(
        %Scope{organization_id: organization_id},
        %HostContext{placement: :mission, mission_id: mission_id}
      )
      when is_binary(organization_id) do
    definitions = Limits.list_limit_definitions(mission_id)
    latest_states = LimitReads.latest_states_for_mission(organization_id, mission_id, [])

    {:ok, status(definitions, latest_states)}
  end

  def load(%Scope{}, %HostContext{}), do: {:error, :unsupported_application_host_context}

  defp status([], latest_states) do
    %Status{
      state: :not_configured,
      label: "Not configured",
      tone: :attention,
      facts: facts([], latest_states)
    }
  end

  defp status(definitions, latest_states) do
    red_count = count_states(latest_states, :red)
    yellow_count = count_states(latest_states, :yellow)

    cond do
      red_count > 0 ->
        %Status{
          state: :red,
          label: "Red limits",
          tone: :blocked,
          facts: facts(definitions, latest_states)
        }

      yellow_count > 0 ->
        %Status{
          state: :yellow,
          label: "Attention",
          tone: :attention,
          facts: facts(definitions, latest_states)
        }

      latest_states == [] ->
        %Status{
          state: :configured,
          label: "Configured",
          tone: :attention,
          facts: facts(definitions, latest_states)
        }

      true ->
        %Status{
          state: :monitoring,
          label: "Monitoring",
          tone: :ready,
          facts: facts(definitions, latest_states)
        }
    end
  end

  defp facts(definitions, latest_states) do
    [
      %{id: "definitions", label: "Definitions", value: Integer.to_string(length(definitions))},
      %{
        id: "departures",
        label: "Current departures",
        value: Integer.to_string(Enum.count(latest_states, & &1.violation))
      }
    ]
  end

  defp count_states(states, normalized_state) do
    Enum.count(states, &(&1.normalized_state == normalized_state))
  end
end
