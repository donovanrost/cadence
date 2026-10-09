defmodule Cadence.Dashboards.VersionAuthoring do
  @moduledoc "Observed-revision publication and non-destructive restoration of saved dashboard versions."
  alias Cadence.Dashboards.{Authoring, AuthoringInput, Documents}
  @max_version 9_007_199_254_740_990

  def execute(scope, mission, dashboard, event, input) do
    with :ok <- Authoring.authorize(scope, mission),
         true <- AuthoringInput.id?(dashboard),
         {:ok, command} <- admit(event, input) do
      effect(scope, mission, dashboard, event, command)
    else
      false -> {:error, :invalid_input}
      error -> normalize(error)
    end
  rescue
    _ -> {:error, :unknown}
  catch
    _, _ -> {:error, :unknown}
  end

  @doc """
  Publishes the latest saved version, observed by the caller as `version`.
  A newer saved version makes this a conflict rather than publishing it unseen.
  """
  def publish_latest(scope, mission, dashboard, version)
      when is_integer(version) and version in 1..@max_version do
    with :ok <- Authoring.authorize(scope, mission),
         true <- AuthoringInput.id?(dashboard),
         {:ok, _} <-
           Documents.publish(scope.organization_id, mission, dashboard, version,
             expected_version: version,
             published_by: scope.user.user_id
           ) do
      {:ok,
       %{version: 1, dashboard_id: dashboard, event: "publish_version", target_version: version}}
    else
      false -> {:error, :invalid_input}
      error -> normalize(error)
    end
  rescue
    _ -> {:error, :unknown}
  catch
    _, _ -> {:error, :unknown}
  end

  def publish_latest(_, _, _, _), do: {:error, :invalid_input}

  def admit(
        event,
        %{"version" => target, "expected_version" => version, "expected_revision" => revision} =
          input
      )
      when event in ["publish_version", "restore_version"] and map_size(input) == 3 and
             is_integer(target) and target in 1..@max_version and
             is_integer(version) and version in 1..@max_version and
             is_integer(revision) and revision in 1..@max_version and target <= version,
      do: {:ok, input}

  def admit(_, _), do: {:error, :invalid_input}

  defp effect(scope, mission, dashboard, event, command) do
    opts = [
      expected_version: command["expected_version"],
      expected_revision: command["expected_revision"]
    ]

    result =
      case event do
        "publish_version" ->
          Documents.publish(
            scope.organization_id,
            mission,
            dashboard,
            command["version"],
            Keyword.put(opts, :published_by, scope.user.user_id)
          )

        "restore_version" ->
          Documents.revert(
            scope.organization_id,
            mission,
            dashboard,
            command["version"],
            Keyword.put(opts, :created_by, scope.user.user_id)
          )
      end

    case result do
      {:ok, _} ->
        {:ok,
         %{
           version: 1,
           dashboard_id: dashboard,
           event: event,
           target_version: command["version"],
           document_version:
             command["expected_version"] + if(event == "restore_version", do: 1, else: 0),
           revision: command["expected_revision"] + 1
         }}

      error ->
        normalize(error)
    end
  end

  defp normalize({:error, :dashboard_revision_conflict}), do: {:error, :conflict}
  defp normalize({:error, {:dashboard_version_conflict, _}}), do: {:error, :conflict}
  defp normalize({:error, {:invalid_dashboard_document, _}}), do: {:error, :invalid_document}

  defp normalize({:error, reason}) when reason in [:forbidden, :invalid_input],
    do: {:error, reason}

  defp normalize({:error, reason})
       when reason in [:dashboard_not_found, :dashboard_archived, :dashboard_version_not_found],
       do: {:error, :unavailable}

  defp normalize(_), do: {:error, :unknown}
end
