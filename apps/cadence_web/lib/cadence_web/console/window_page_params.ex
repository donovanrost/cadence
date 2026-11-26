defmodule CadenceWeb.Console.WindowPageParams do
  @moduledoc "Page parameters shared by the console's pass and contact findings windows."

  alias CadenceWeb.Console.Problem

  @max_limit 500

  def parse(params, default_limit) do
    with {:ok, limit} <- limit(params["limit"], default_limit),
         {:ok, cursor} <- cursor(params["cursor"]) do
      {:ok, %{limit: limit, cursor: cursor}}
    end
  end

  defp limit(nil, default), do: {:ok, default}

  defp limit(value, _default) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n in 1..@max_limit -> {:ok, n}
      _invalid -> invalid_limit()
    end
  end

  defp limit(_value, _default), do: invalid_limit()

  defp invalid_limit,
    do: {:error, {:invalid_params, %{limit: "must be an integer from 1 to #{@max_limit}"}}}

  defp cursor(value) when value in [nil, ""], do: {:ok, nil}
  defp cursor(value) when is_binary(value), do: {:ok, value}
  defp cursor(_value), do: {:error, :invalid_cursor}

  def cursor_error(conn),
    do:
      Problem.respond(conn, :invalid_params, %{
        cursor: "is not valid for this window"
      })
end
