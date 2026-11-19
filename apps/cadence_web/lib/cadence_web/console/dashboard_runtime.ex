defmodule CadenceWeb.Console.DashboardRuntime do
  @moduledoc """
  A dashboard runtime (`from`/`to` range and one `spacecraft_id`) admitted the way D5 admits the
  viewer's query (`CadenceWeb.OpsWorkspaceURL`), for the authoring endpoints that take it in a
  JSON body. A spacecraft that isn't the mission's is refused later by the resolver
  (`:invalid_scope`).
  """

  alias CadenceWeb.OpsWorkspaceURL

  @spec admit(map() | nil) :: {:ok, map()} | {:error, :invalid_range | :invalid_scope}
  def admit(nil), do: admit(%{})

  def admit(%{} = params) do
    spacecraft_id = params["spacecraft_id"]

    with :ok <- spacecraft(spacecraft_id),
         {:ok, runtime} <-
           params
           |> Map.take(~w(from to))
           |> Map.filter(fn {_key, value} -> is_binary(value) end)
           |> put_spacecraft(spacecraft_id)
           |> OpsWorkspaceURL.admit() do
      {:ok, runtime}
    else
      {:error, :invalid_scope} -> {:error, :invalid_scope}
      {:error, _invalid_context} -> {:error, :invalid_range}
    end
  end

  def admit(_params), do: {:error, :invalid_range}

  defp spacecraft(nil), do: :ok
  defp spacecraft(id) when is_binary(id) and byte_size(id) in 1..256, do: :ok
  defp spacecraft(_invalid), do: {:error, :invalid_scope}

  defp put_spacecraft(map, nil), do: map
  defp put_spacecraft(map, id), do: Map.put(map, "spacecraft", id)
end
