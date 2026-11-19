defmodule CadenceWeb.Console.DashboardDefaults do
  @moduledoc """
  D9 "save the current range and scope as the default": the `runtime_defaults` command built from
  the staged document's defaults and the viewer's admitted runtime. Ported from the legacy page's
  save, which went with the legacy pages (L8a, DECISIONS #79).
  """

  alias Cadence.Dashboards.{AuthoringDefaults, Document}

  @doc """
  `{:ok, command}` to append, `:none` when neither flag is set, or `{:error, :invalid_defaults}`.
  `flags`: `%{"time" => bool, "scope" => bool}`.
  """
  @spec command(Document.t(), map(), map() | nil) :: {:ok, map()} | :none | {:error, atom()}
  def command(%Document{} = staged, runtime, %{} = flags)
      when :erlang.map_get("time", flags) == true or :erlang.map_get("scope", flags) == true do
    with {:ok, json} <- AuthoringDefaults.encode(staged.defaults),
         {:ok, defaults} <- Jason.decode(json),
         {:ok, encoded} <- AuthoringDefaults.encode(apply_flags(defaults, runtime, flags)) do
      {:ok, %{"event" => "runtime_defaults", "input" => %{"defaults_json" => encoded}}}
    else
      _invalid -> {:error, :invalid_defaults}
    end
  end

  def command(_staged, _runtime, _flags), do: :none

  defp apply_flags(defaults, runtime, flags) do
    defaults
    |> then(&if(flags["time"] == true, do: put_time(&1, runtime.time_context), else: &1))
    |> then(&if(flags["scope"] == true, do: put_scope(&1, runtime.scope_context), else: &1))
  end

  defp put_time(defaults, time) do
    kept = Map.take(Map.get(defaults, "time") || %{}, ["axis"])

    selected =
      case time do
        %{mode: "live", window_seconds: seconds} ->
          %{"mode" => "live", "window_seconds" => seconds}

        %{mode: mode, from: from, to: to} ->
          %{"mode" => mode, "from" => iso(from), "to" => iso(to)}

        _other ->
          %{"mode" => "live"}
      end

    Map.put(defaults, "time", Map.merge(kept, selected))
  end

  defp put_scope(defaults, %{spacecraft_id: id}) when is_binary(id),
    do:
      Map.put(defaults, "scope", %{
        "primary" => %{"kind" => "spacecraft", "mode" => "one", "ids" => [id]},
        "spacecraft_id" => id
      })

  defp put_scope(defaults, _scope), do: Map.delete(defaults, "scope")

  defp iso(%DateTime{} = at), do: DateTime.to_iso8601(at)
  defp iso(other), do: other
end
