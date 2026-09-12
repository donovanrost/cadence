defmodule Cadence.Reads.Dashboards.Creation do
  @moduledoc "Authorized semantic dashboard creation context."
  alias Cadence.Dashboards.{Creation, Document, Documents}

  def load(scope, mission, params \\ %{}) do
    with :ok <- Creation.authorize(scope, mission),
         {:ok, mode, source_id} <- parameters(params),
         {:ok, source} <- source(scope, mission, mode, source_id) do
      {:ok, %{version: 1, mission_id: mission, mode: mode, source: source}}
    end
  rescue
    _ -> {:error, :unavailable}
  catch
    _, _ -> {:error, :unavailable}
  end

  defp parameters(params) when map_size(params) == 0, do: {:ok, "new", nil}

  defp parameters(%{"mode" => mode} = params)
       when map_size(params) == 1 and mode in ~w(new import),
       do: {:ok, mode, nil}

  defp parameters(%{"mode" => "clone", "source_dashboard_id" => source} = params)
       when map_size(params) == 2 and is_binary(source) and byte_size(source) in 1..256 do
    if String.valid?(source), do: {:ok, "clone", source}, else: {:error, :invalid_params}
  end

  defp parameters(_), do: {:error, :invalid_params}

  defp source(_scope, _mission, mode, nil) when mode in ~w(new import), do: {:ok, nil}

  defp source(scope, mission, "clone", id) do
    with {:ok, document} <- Documents.fetch_for_mode(scope.organization_id, mission, id, :edit) do
      {:ok,
       %{
         id: document.dashboard_id,
         name: document.name,
         description: document.description,
         version: Document.version(document),
         widget_count: length(document.placements)
       }}
    end
  end
end
