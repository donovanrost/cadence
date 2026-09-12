defmodule CadenceWeb.OpsDiagnosticsURL do
  @moduledoc "Admits diagnostics view selection separately from bounded viewer runtime context."
  alias CadenceWeb.OpsWorkspaceURL

  @collections ~w(plan requests frames cache source_execution refresh invalidation)
  @selection_keys ~w(collection row filter)

  def admit(params) when is_map(params) do
    runtime_params = Map.drop(params, @selection_keys)
    collection = Map.get(params, "collection", "plan")
    row = Map.get(params, "row")
    filter = Map.get(params, "filter", "")

    with true <- collection in @collections,
         true <- valid_row?(row),
         true <- valid_filter?(filter),
         {:ok, runtime} <- OpsWorkspaceURL.admit(runtime_params) do
      {:ok,
       %{
         selection: %{collection: collection, row: row, filter: filter},
         runtime: runtime,
         runtime_query: Map.drop(runtime_params, ~w(mission_id dashboard_id))
       }}
    else
      _ -> {:error, :invalid_context}
    end
  end

  def admit(_), do: {:error, :invalid_context}

  defp valid_row?(nil), do: true
  defp valid_row?(row) when is_binary(row), do: Regex.match?(~r/\A[a-f0-9]{64}\z/, row)
  defp valid_row?(_), do: false

  defp valid_filter?(filter) when is_binary(filter) and byte_size(filter) <= 256 do
    String.valid?(filter) and not Regex.match?(~r/[\x00-\x1f\x7f]/u, filter)
  end

  defp valid_filter?(_), do: false
end
