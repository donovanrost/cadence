defmodule Cadence.Dashboards.SettingsInput do
  @moduledoc "Bounded semantic input for dashboard settings, sharing and lifecycle commands."
  alias Cadence.Dashboards.{AuthoringDefaults, AuthoringInput}
  @max_version 9_007_199_254_740_990
  @observed ~w(expected_version expected_revision)
  @visibility ~w(authorized_runtime_data definition_only)

  def admit(event, input) when is_map(input) do
    with true <- version?(input["expected_version"]),
         true <- version?(input["expected_revision"]),
         {:ok, fields} <- fields(event, Map.drop(input, @observed)) do
      {:ok, Map.merge(Map.take(input, @observed), fields)}
    else
      _ -> {:error, :invalid_input}
    end
  end

  def admit(_, _), do: {:error, :invalid_input}

  def query(params) when is_map(params) do
    keys = ~w(after_share after_snapshot after_deployment)

    if Map.keys(params) -- keys == [] and Enum.all?(Map.values(params), &optional_id?/1),
      do: {:ok, Map.new(keys, &{&1, params[&1]})},
      else: {:error, :invalid_input}
  end

  def query(_), do: {:error, :invalid_input}

  def tags?(tags) when is_list(tags) do
    length(tags) <= 32 and Enum.all?(tags, &text?(&1, 64, false)) and
      Enum.uniq(tags) == tags and Enum.all?(tags, &(String.trim(&1) == &1))
  end

  def tags?(_), do: false
  def version?(value), do: is_integer(value) and value in 1..@max_version

  def text?(value, max, empty?) when is_binary(value),
    do: String.valid?(value) and byte_size(value) <= max and (empty? or String.trim(value) != "")

  def text?(_, _, _), do: false

  defp fields("save_settings", fields) do
    with true <- exact?(fields, ~w(name description tags defaults_json)),
         true <- text?(fields["name"], 120, false),
         true <- text?(fields["description"], 500, true),
         true <- tags?(fields["tags"]),
         {:ok, defaults} <- AuthoringDefaults.decode(fields["defaults_json"]),
         :ok <- AuthoringDefaults.validate(defaults) do
      {:ok, fields |> Map.delete("defaults_json") |> Map.put("defaults", defaults)}
    else
      _ -> :error
    end
  end

  defp fields("create_share", fields) do
    if exact?(fields, ~w(data_visibility expires_in_hours)) and
         fields["data_visibility"] in @visibility and expiration?(fields["expires_in_hours"]),
       do: {:ok, fields},
       else: :error
  end

  defp fields("create_snapshot", fields) do
    if exact?(fields, ~w(data_visibility)) and fields["data_visibility"] in @visibility,
      do: {:ok, fields},
      else: :error
  end

  defp fields("revoke_share", fields) do
    if exact?(fields, ~w(share_id)) and AuthoringInput.id?(fields["share_id"]),
      do: {:ok, fields},
      else: :error
  end

  defp fields("archive_dashboard", fields) when fields == %{}, do: {:ok, fields}
  defp fields(_, _), do: :error
  defp exact?(fields, keys), do: Enum.sort(Map.keys(fields)) == Enum.sort(keys)
  defp optional_id?(nil), do: true
  defp optional_id?(id), do: AuthoringInput.id?(id)
  defp expiration?(nil), do: true
  defp expiration?(hours), do: is_integer(hours) and hours in 1..8760
end
