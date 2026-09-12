defmodule Cadence.Reads.Dashboards.ObservableChoices do
  @moduledoc "Authorized, bounded observable choices for the displayed dashboard draft."
  alias Cadence.Applications.HostContext

  alias Cadence.Dashboards.{
    Authoring,
    AuthoringDraft,
    AuthoringInput,
    AuthoringWidget,
    Document,
    Documents,
    OperationalObservable
  }

  alias Cadence.Extensions.Presentation.ReferenceDefinition
  alias Cadence.Reads.ApplicationSurfaces.ReferenceProviders.CanonicalTelemetryPoints

  @limit 50

  def search(scope, mission, dashboard, input) do
    with :ok <- Authoring.authorize(scope, mission),
         true <- AuthoringInput.id?(dashboard),
         {:ok, query, fields, version} <- admit(input),
         {:ok, document} <-
           Documents.fetch_for_mode(scope.organization_id, mission, dashboard, :edit),
         true <-
           document.organization_id == scope.organization_id and
             document.mission_id == mission and document.dashboard_id == dashboard,
         true <- Document.version(document) == version,
         {:ok, options, more} <- choices(scope, document, query, fields),
         true <- bounded_options?(options) do
      {:ok,
       %{
         version: 1,
         organization_id: scope.organization_id,
         mission_id: mission,
         dashboard_id: dashboard,
         document_version: version,
         query: query,
         options: options,
         more: more
       }}
    else
      _ -> {:error, :unavailable}
    end
  rescue
    _ -> {:error, :unavailable}
  catch
    _, _ -> {:error, :unavailable}
  end

  def staged(scope, %AuthoringDraft{} = draft, input) when is_map(input) do
    with true <- input["expected_revision"] == draft.revision,
         {:ok, query, fields, version} <- admit(Map.delete(input, "expected_revision")),
         {:ok, document} <- AuthoringDraft.current(scope, draft),
         true <- Document.version(document) == version,
         {:ok, options, more} <- choices(scope, document, query, fields),
         true <- bounded_options?(options) do
      {:ok,
       %{
         version: 2,
         organization_id: document.organization_id,
         mission_id: document.mission_id,
         dashboard_id: document.dashboard_id,
         document_version: version,
         staging_revision: draft.revision,
         query: query,
         options: options,
         more: more
       }}
    else
      _ -> {:error, :unavailable}
    end
  rescue
    _ -> {:error, :unavailable}
  catch
    _, _ -> {:error, :unavailable}
  end

  def staged(_, _, _), do: {:error, :unavailable}

  defp admit(%{"query" => query, "fields" => fields, "expected_version" => version} = input)
       when map_size(input) == 3 and is_integer(version) and version in 1..9_007_199_254_740_990 do
    if AuthoringInput.text?(query, 256) and AuthoringInput.widget_fields?(fields),
      do: {:ok, String.trim(query), fields, version},
      else: :error
  end

  defp admit(_), do: :error

  defp bounded_options?(options) do
    length(options) <= @limit and Enum.all?(options, &bounded_option?/1)
  end

  defp bounded_option?(option) do
    AuthoringInput.id?(option.value) and not String.match?(option.value, ~r/[\x00-\x1f]/) and
      AuthoringInput.text?(option.label, 512) and
      AuthoringInput.text?(option.description, 4096)
  end

  defp choices(_scope, _document, _query, %{"type" => type})
       when type in ~w(event_timeline constellation_health), do: {:ok, [], false}

  defp choices(_scope, document, query, %{"binding_source" => "operational_observables"} = fields) do
    options =
      OperationalObservable.list()
      |> Enum.filter(&OperationalObservable.backed?(&1.observable_id))
      |> Enum.map(&%{value: &1.observable_id, label: &1.name, description: &1.description})
      |> Enum.filter(&(matches?(&1, query) and supported?(document, fields, &1.value)))
      |> Enum.sort_by(& &1.value)

    {:ok, Enum.take(options, @limit), length(options) > @limit}
  end

  defp choices(scope, document, query, fields) do
    context = %HostContext{placement: :mission, mission_id: document.mission_id}

    definition = %ReferenceDefinition{
      provider_id: "cadence.telemetry.canonical_points",
      version: 1
    }

    with {:ok, page} <- CanonicalTelemetryPoints.search(scope, context, definition, query, @limit) do
      options =
        page.options
        |> Enum.filter(&supported?(document, fields, &1.value))
        |> Enum.map(&Map.take(&1, [:value, :label, :description]))

      {:ok, options, page.more?}
    end
  end

  defp supported?(document, fields, id) do
    fields =
      AuthoringWidget.defaults()
      |> Map.merge(
        Map.take(
          fields,
          ~w(type binding_source mode spacecraft_id scope_kind scope_id repeat_over)
        )
      )
      |> Map.put("title", "Observable choice")

    match?({:ok, _}, AuthoringWidget.build(document, fields, [id], nil))
  end

  defp matches?(option, query) do
    query = String.downcase(query)

    Enum.any?(
      [option.value, option.label, option.description],
      &String.contains?(String.downcase(&1), query)
    )
  end
end
