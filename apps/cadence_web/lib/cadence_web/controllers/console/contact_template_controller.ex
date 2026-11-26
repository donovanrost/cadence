defmodule CadenceWeb.Console.ContactTemplateController do
  @moduledoc """
  Contact planning summary (CP1) and targeted requirement templates (CP3) under
  `/api/v1/missions/:mission_id/contact-planning`. Contract:
  docs/apogee/api/scheduling.md.
  """

  use CadenceWeb, :controller

  alias Cadence.ContactPlanning.{TemplateDayReview, TemplateSchema}
  alias Cadence.Control.PlanningTemplates
  alias Cadence.Reads.ContactPlanOverview
  alias CadenceWeb.Console.{ConfigJSON, Problem}

  @preview_days 1..31

  def summary(conn, _params),
    do: ok(conn, PlanningTemplates.summary(conn.assigns.current_scope, mission_id(conn)))

  def schema(conn, _params),
    do: ok(conn, %{fields: TemplateSchema.fields(), defaults: TemplateSchema.defaults()})

  def index(conn, _params),
    do: ok(conn, %{templates: PlanningTemplates.list(org_id(conn), mission_id(conn))})

  def show(conn, %{"template_id" => id}) do
    case PlanningTemplates.get(org_id(conn), mission_id(conn), id) do
      {:ok, template} -> ok(conn, template)
      {:error, reason} -> error(conn, reason)
    end
  end

  @doc """
  Dry run: the open drafts a new version of this template would supersede, and the days it won't
  regenerate (U48, DECISIONS #86: `decided` planned_or_started / closed / canceled).
  """
  def supersedes(conn, %{"template_id" => id}) do
    drafts = ContactPlanOverview.would_supersede(org_id(conn), mission_id(conn), {:template, id})
    decided = TemplateDayReview.decided(org_id(conn), mission_id(conn), id, DateTime.utc_now())
    ok(conn, %{drafts: drafts, decided: decided})
  end

  @doc "Dry run: the open drafts a new version of this requirement would supersede."
  def requirement_supersedes(conn, %{"requirement_id" => id}),
    do: drafts(conn, {:requirement, id})

  defp drafts(conn, subject) do
    drafts = ContactPlanOverview.would_supersede(org_id(conn), mission_id(conn), subject)
    ok(conn, %{drafts: drafts})
  end

  def create(conn, params), do: save(conn, nil, params)
  def update(conn, %{"template_id" => id} = params), do: save(conn, id, params)

  @doc "`{name?, document, target, days?}` → the effect over the next `days` (default 1)."
  def preview(conn, params) do
    with {:ok, days} <- days(params["days"]),
         from = DateTime.utc_now() |> DateTime.truncate(:second),
         until = DateTime.add(from, days * 86_400, :second),
         {:ok, effect} <-
           PlanningTemplates.preview(
             conn.assigns.current_scope,
             mission_id(conn),
             params,
             from,
             until
           ) do
      ok(conn, Map.drop(effect, [:spacecraft_ids]))
    else
      {:error, reason} -> error(conn, reason)
    end
  end

  # §11 L2: pause, resume and close a template (reason required; the version doesn't move).
  def pause(conn, %{"template_id" => id} = params), do: transition(conn, id, :pause, params)
  def activate(conn, %{"template_id" => id} = params), do: transition(conn, id, :activate, params)
  def close(conn, %{"template_id" => id} = params), do: transition(conn, id, :close, params)

  defp transition(conn, id, action, params) do
    case PlanningTemplates.transition(
           conn.assigns.current_scope,
           mission_id(conn),
           id,
           action,
           params
         ) do
      {:ok, result} -> ok(conn, result)
      {:error, reason} -> error(conn, reason)
    end
  end

  defp save(conn, id, params) do
    case PlanningTemplates.save(conn.assigns.current_scope, mission_id(conn), id, params) do
      {:ok, result} -> conn |> put_status(:created) |> json(%{data: ConfigJSON.encode(result)})
      {:error, :stale_contact_requirement_template_version} -> stale(conn, id)
      {:error, reason} -> error(conn, reason)
    end
  end

  # A stale edit names the template's current version, like the other writes (drift sweep).
  defp stale(conn, id) do
    case PlanningTemplates.get(conn.assigns.current_scope.organization_id, mission_id(conn), id) do
      {:ok, %{version: current}} -> error(conn, {:version_conflict, current})
      _gone -> error(conn, :stale_contact_requirement_template_version)
    end
  end

  defp days(nil), do: {:ok, 1}
  defp days(n) when is_integer(n) and n in @preview_days, do: {:ok, n}
  defp days(_n), do: {:error, {:invalid_params, %{days: "must be 1 to 31"}}}

  defp ok(conn, data), do: json(conn, %{data: ConfigJSON.encode(data)})

  defp error(conn, {:invalid_params, details}),
    do: Problem.respond(conn, :invalid_params, details)

  defp error(conn, {:invalid_contact_requirement_template, message}),
    do: Problem.respond(conn, :invalid_params, %{document: message})

  defp error(conn, {:template_target_unknown_spacecraft, ids}),
    do:
      Problem.respond(conn, :invalid_params, %{target: "unknown spacecraft", spacecraft_ids: ids})

  defp error(conn, :template_target_profile_not_found),
    do: Problem.respond(conn, :invalid_params, %{target: "unknown profile"})

  defp error(conn, :contact_requirement_template_spacecraft_not_found),
    do: Problem.respond(conn, :invalid_params, %{target: "unknown spacecraft"})

  defp error(conn, {:duplicate_operation, id}),
    do: Problem.respond(conn, :duplicate_operation, %{template_id: id})

  defp error(conn, {:version_conflict, current}),
    do: Problem.respond(conn, :version_conflict, %{expected_version: current})

  defp error(conn, {:template_transition_not_allowed, state}),
    do: Problem.respond(conn, :template_transition_not_allowed, %{state: state})

  defp error(conn, :stale_contact_requirement_template_version),
    do: Problem.respond(conn, :version_conflict)

  defp error(conn, reason)
       when reason in [:template_not_found, :contact_requirement_template_not_found],
       do: Problem.respond(conn, :template_not_found)

  defp error(conn, reason) when reason in [:forbidden, :scope_mismatch],
    do: Problem.respond(conn, :forbidden)

  defp error(conn, reason) when is_atom(reason), do: Problem.respond(conn, reason)

  defp error(conn, reason),
    do: Problem.respond(conn, :template_rejected, %{reason: inspect(reason)})

  defp org_id(conn), do: conn.assigns.current_scope.organization_id
  defp mission_id(conn), do: conn.assigns.current_mission.mission_id
end
