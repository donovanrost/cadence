defmodule Cadence.Reads.Dashboards.Authors do
  @moduledoc "Display names for the people who saved dashboard versions."
  alias Cadence.Accounts

  @doc "Maps each user id to a display name, falling back to the email, then the id."
  @spec names([binary() | nil]) :: %{binary() => binary()}
  def names(ids) do
    ids
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Map.new(fn id ->
      case Accounts.fetch_user(id) do
        {:ok, user} -> {id, user.display_name || user.email}
        _ -> {id, id}
      end
    end)
  end
end
