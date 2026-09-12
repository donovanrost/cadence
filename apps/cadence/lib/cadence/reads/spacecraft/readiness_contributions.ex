defmodule Cadence.Reads.Spacecraft.ReadinessContributions do
  @moduledoc "Host admission for versioned data-only spacecraft readiness contributions."
  alias Cadence.Applications.{HostContext, Status}
  alias Cadence.Reads.Applications.StatusProvider
  alias Cadence.Reads.Comms.SpacecraftReadiness
  @slot "spacecraft.readiness"
  @providers [{"comms.routing", "Routing", SpacecraftReadiness}]

  def load(scope, mission, spacecraft, applications) do
    context = HostContext.spacecraft(mission.mission_id, spacecraft.spacecraft_id)
    href = "/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}"

    scope_data = %{
      "organizationId" => mission.organization_id,
      "missionId" => mission.mission_id,
      "spacecraftId" => spacecraft.spacecraft_id
    }

    providers =
      Enum.map(@providers, fn {id, title, provider} ->
        result = StatusProvider.invoke(provider, scope, context)

        from_result(id, title, scope_data, result, %{
          "label" => "Review Routing",
          "href" => href <> "/routing"
        })
      end)

    providers ++
      Enum.map(applications, fn item ->
        from_result(
          "application." <> item.application_key,
          item.display_name,
          scope_data,
          {:ok, item.status},
          %{"label" => "Review Applications", "href" => href <> "/applications"}
        )
      end)
  end

  @doc false
  def from_result(id, title, context, result, action) do
    case result do
      {:ok, %Status{state: :unavailable}} ->
        unavailable(id, title, context, action)

      {:ok, %Status{} = status} ->
        if Status.valid?(status) do
          %{
            "id" => id,
            "slot" => @slot,
            "version" => 1,
            "title" => title,
            "context" => context,
            "availability" => "available",
            "status" => %{"tone" => to_string(status.tone), "label" => status.label},
            "details" => Enum.map(status.facts, &%{"label" => &1.label, "value" => &1.value}),
            "action" => action
          }
        else
          unavailable(id, title, context, action)
        end

      _ ->
        unavailable(id, title, context, action)
    end
  end

  defp unavailable(id, title, context, action),
    do: %{
      "id" => id,
      "slot" => @slot,
      "version" => 1,
      "title" => title,
      "context" => context,
      "availability" => "unavailable",
      "status" => %{"tone" => "blocked", "label" => "Unavailable"},
      "details" => [],
      "action" => action
    }
end
