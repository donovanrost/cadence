defmodule Cadence.Dashboards.Authoring do
  @moduledoc """
  Authorized, observed-version dashboard authoring commands.

  The caller supplies the version the operator actually saw. Commands never
  replace that precondition with a freshly fetched version. Persistence retains
  its optimistic-lock transaction and publication-readiness checks. Frontend
  delivery, page tokens and interaction sequencing are separate host concerns.
  """
  alias Cadence.Auth.{Policy, Scope}

  alias Cadence.Dashboards.{
    AuthoringChanges,
    AuthoringErrors,
    AuthoringInput,
    Document,
    Documents
  }

  alias Cadence.Missions

  def authorize(
        %Scope{actor_kind: :user, organization_id: org, user: %{user_id: user}} = scope,
        mission
      ) do
    with true <- Enum.all?([org, user, mission], &AuthoringInput.id?/1),
         true <- scope.mission_id in [nil, mission],
         :ok <-
           Policy.authorize(scope, :author_dashboards, %{
             organization_id: org,
             mission_id: mission
           }),
         {:ok, _} <- Missions.fetch_mission(org, mission) do
      :ok
    else
      _ -> {:error, :forbidden}
    end
  end

  def authorize(_, _), do: {:error, :forbidden}

  def execute(scope, mission, dashboard, event, input) do
    with :ok <- authorize(scope, mission),
         true <- AuthoringInput.id?(dashboard),
         {:ok, version, payload} <- AuthoringInput.admit(event, input),
         {:ok, document} <-
           Documents.fetch_for_mode(scope.organization_id, mission, dashboard, :edit),
         true <-
           document.organization_id == scope.organization_id and document.mission_id == mission and
             document.dashboard_id == dashboard,
         :ok <- observed_version(document, version) do
      command(scope, document, event, payload, version)
    else
      false -> {:error, :invalid_input}
      error -> AuthoringErrors.normalize(error)
    end
  rescue
    _ -> {:error, :unknown}
  catch
    _, _ -> {:error, :unknown}
  end

  defp observed_version(document, version) do
    if Document.version(document) == version, do: :ok, else: {:error, :conflict}
  end

  defp command(scope, document, "publish", _payload, version) do
    case Documents.publish(
           scope.organization_id,
           document.mission_id,
           document.dashboard_id,
           version,
           expected_version: version,
           published_by: scope.user.user_id
         ) do
      {:ok, published} -> {:ok, receipt(document.dashboard_id, published.version, "publish", %{})}
      error -> AuthoringErrors.normalize(error)
    end
  end

  defp command(scope, document, event, payload, version) do
    with {:ok, next, details} <- AuthoringChanges.apply(document, event, payload),
         {:ok, saved} <-
           Documents.update(
             scope.organization_id,
             document.mission_id,
             document.dashboard_id,
             next,
             expected_version: version,
             created_by: scope.user.user_id,
             change_summary: "Dashboard editor: " <> event
           ) do
      {:ok, receipt(saved.dashboard_id, Document.version(saved), event, details)}
    else
      error -> AuthoringErrors.normalize(error)
    end
  end

  defp receipt(id, version, event, details),
    do:
      Map.merge(%{version: 1, dashboard_id: id, document_version: version, event: event}, details)
end
