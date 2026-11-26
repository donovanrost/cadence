defmodule Cadence.Platform.ExitShape do
  @moduledoc """
  An exit reason or thrown value, said without its data, for a log line (#263; ca-security,
  api-ops). A `GenServer.call` timeout's reason carries the call's arguments (whole structs, row
  values), so a log names only its shape: the reason and the module and function that exited.
  """

  @spec describe(term()) :: binary()
  def describe({reason, {module, function, args}})
      when is_atom(module) and is_atom(function) and is_list(args),
      do: "#{shape(reason)} in #{inspect(module)}.#{function}"

  def describe(reason), do: shape(reason)

  defp shape(reason) when is_atom(reason), do: inspect(reason)
  defp shape({reason, _detail}) when is_atom(reason), do: inspect(reason)
  defp shape(reason) when is_tuple(reason), do: "a #{tuple_size(reason)}-tuple"
  defp shape(_reason), do: "a value"
end
