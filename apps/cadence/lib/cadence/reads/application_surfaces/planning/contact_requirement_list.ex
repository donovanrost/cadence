defmodule Cadence.Reads.ApplicationSurfaces.Planning.ContactRequirementList do
  @moduledoc "Bounded current requirement ledger for an authorized mission surface."
  alias Cadence.Auth.Scope
  alias Cadence.ContactPlanning.ContactRequirements

  @states %{"all" => nil, "active" => :active, "closed" => :closed, "canceled" => :canceled}

  def admit_query(params) when is_map(params) and map_size(params) <= 2 do
    with true <-
           Enum.all?(params, fn {key, value} ->
             key in ["page", "state"] and is_binary(value) and byte_size(value) <= 16
           end),
         page = Map.get(params, "page", "1"),
         true <- Regex.match?(~r/\A[1-9][0-9]{0,6}\z/, page),
         {number, ""} when number <= 1_000_000 <- Integer.parse(page),
         state = Map.get(params, "state", "all"),
         true <- Map.has_key?(@states, state) do
      {:ok, %{page: number, state: state}}
    else
      _ -> {:error, :invalid_requirement_list_query}
    end
  end

  def admit_query(_), do: {:error, :invalid_requirement_list_query}

  def load(%Scope{} = scope, mission, params) do
    with {:ok, query} <- admit_query(Map.delete(params, "mission_id")),
         {:ok, result} <-
           ContactRequirements.list_page(
             scope.organization_id,
             mission.mission_id,
             query.page,
             Map.fetch!(@states, query.state)
           ) do
      model = %{
        contract_version: 1,
        context: %{organization_id: scope.organization_id, mission_id: mission.mission_id},
        page: page(mission.mission_id),
        query: %{page: query.page, state: query.state},
        filters:
          Enum.map(["all", "active", "closed", "canceled"], fn state ->
            %{
              id: "requirements-filter-#{state}",
              label: String.capitalize(state),
              href: href(mission.mission_id, 1, state),
              active: state == query.state
            }
          end),
        pagination: %{
          label: "Page #{query.page}",
          previous_href:
            if(query.page > 1, do: href(mission.mission_id, query.page - 1, query.state)),
          next_href: if(result.more?, do: href(mission.mission_id, query.page + 1, query.state))
        },
        requirements: Enum.map(result.entries, &row(mission.mission_id, &1))
      }

      if byte_size(Jason.encode!(model)) <= 131_072,
        do: {:ok, model},
        else: {:error, :requirement_list_too_large}
    end
  end

  defp row(mission_id, {requirement, version}) do
    id = requirement.contact_requirement_id

    {label, tone} =
      case version.priority do
        :critical -> {"Critical", "error"}
        :high -> {"High", "warning"}
        :routine -> {"Routine", "neutral"}
      end

    %{
      id: id,
      __dom_id: "requirement-" <> Base.url_encode64(id, padding: false),
      priority: %{label: label, tone: tone, class: "text-" <> tone},
      version_direction: "v#{version.version} · #{version.service_direction}",
      intent_label: version.contact_intent |> String.replace("_", " ") |> String.capitalize(),
      outcome_detail: outcome(version),
      window: %{
        label: "Acceptable window (UTC)",
        detail:
          DateTime.to_iso8601(version.earliest_start) <>
            " → " <> DateTime.to_iso8601(version.latest_end)
      },
      lifecycle: %{
        label: requirement.lifecycle_state |> Atom.to_string() |> String.capitalize(),
        detail: "Requirement lifecycle, not reservation status"
      },
      detail_href: "/missions/#{segment(mission_id)}/ops/requirements/#{segment(id)}"
    }
  end

  defp outcome(%{success_measure: :any_contact}), do: "Any eligible contact"

  defp outcome(%{success_measure: :minimum_duration} = version),
    do: "At least #{version.minimum_duration_seconds} seconds"

  defp outcome(%{success_measure: :minimum_data_volume} = version),
    do: "At least #{version.minimum_data_volume_bytes} bytes"

  defp outcome(%{success_measure: :contact_count} = version),
    do:
      "#{version.contact_count} contacts · at least #{version.minimum_separation_seconds} seconds apart"

  defp href(mission_id, page, state),
    do:
      "/missions/#{segment(mission_id)}/ops/requirements?" <>
        URI.encode_query(%{"page" => page, "state" => state})

  defp segment(id), do: URI.encode(id, &URI.char_unreserved?/1)

  defp page(mission_id),
    do: %{
      "id" => "ops-contact-requirements-page",
      "header" => %{
        "eyebrow" => "Mission operations / planning horizon",
        "title" => "Contact Requirements",
        "description" =>
          "Declare the mission outcome first. Cadence searches every ready provider route, preserves their evidence, and lets operators commit an exact plan.",
        "create_action" => %{
          "id" => "new-contact-requirement-link",
          "label" => "Declare need",
          "href" => "/missions/#{segment(mission_id)}/ops/requirements/new"
        }
      },
      "journey_steps" => [
        %{"number" => "01", "label" => "Need", "detail" => "Mission outcome", "active" => true},
        %{
          "number" => "02",
          "label" => "Options",
          "detail" => "Provider evidence",
          "active" => false
        },
        %{"number" => "03", "label" => "Plan", "detail" => "Exact commitment", "active" => false},
        %{
          "number" => "04",
          "label" => "Reserved",
          "detail" => "Provider capacity",
          "active" => false
        }
      ],
      "empty_state" => %{
        "id" => "contact-requirements-empty",
        "title" => "No matching contact requirements",
        "description" => "Choose another lifecycle or page, or declare a new mission need."
      },
      "list_id" => "contact-requirements"
    }
end
