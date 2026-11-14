defmodule Cadence.Dashboards.PlaylistInput do
  @moduledoc "Bounded playlist authoring inputs."
  alias Cadence.Dashboards.AuthoringInput

  def create(input) when is_map(input) do
    with true <-
           Enum.sort(Map.keys(input)) ==
             Enum.sort(~w(name description dashboard_ids dwell_seconds wallboard_mode)),
         true <- AuthoringInput.text?(input["name"], 120) and String.trim(input["name"]) != "",
         true <- AuthoringInput.text?(input["description"], 4096),
         true <- ids?(input["dashboard_ids"]),
         true <- is_integer(input["dwell_seconds"]) and input["dwell_seconds"] in 5..900,
         true <- is_boolean(input["wallboard_mode"]) do
      {:ok, Map.update!(input, "name", &String.trim/1)}
    else
      _ -> {:error, :invalid_input}
    end
  end

  def create(_), do: {:error, :invalid_input}

  @doc "A playlist update (Q6): any of create's fields; absent means unchanged."
  def update(input) when is_map(input) and map_size(input) > 0 do
    valid? =
      Map.keys(input) -- ~w(name description dashboard_ids dwell_seconds wallboard_mode) == [] and
        Enum.all?(input, fn
          {"name", name} -> AuthoringInput.text?(name, 120) and String.trim(name) != ""
          {"description", text} -> AuthoringInput.text?(text, 4096)
          {"dashboard_ids", ids} -> ids?(ids)
          {"dwell_seconds", n} -> is_integer(n) and n in 5..900
          {"wallboard_mode", flag} -> is_boolean(flag)
        end)

    if valid?,
      do: {:ok, if(input["name"], do: Map.update!(input, "name", &String.trim/1), else: input)},
      else: {:error, :invalid_input}
  end

  def update(_), do: {:error, :invalid_input}

  defp ids?(ids) when is_list(ids),
    do: length(ids) in 1..100 and Enum.all?(ids, &AuthoringInput.id?/1)

  defp ids?(_), do: false
end
