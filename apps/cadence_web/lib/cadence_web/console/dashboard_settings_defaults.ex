defmodule CadenceWeb.Console.DashboardSettingsDefaults do
  @moduledoc """
  D14/D15 `defaults {time, scope}` ↔ the dashboard's stored defaults (`AuthoringDefaults` JSON).

  - `time`: `{mode: "relative", range: "now-6h"}` is a live window (`window_seconds`);
    `{mode: "absolute", from, to}` a fixed range (ISO 8601); `null` none. Other stored modes
    (archive, replay) read as `null` and are kept when a save leaves `time` alone.
  - `scope`: `{mode: "fixed", spacecraft_id}` pins a spacecraft; `{mode: "context" | "fleet"}` and
    `null` store no spacecraft (the viewer's context), and read back as `null`.

  Keys the console doesn't edit (`axis`, `data`, `limits`) are kept.
  """

  alias Cadence.Dashboards.{AuthoringDefaults, TimeRange}

  @units [{604_800, "w"}, {86_400, "d"}, {3_600, "h"}, {60, "m"}, {1, "s"}]

  @spec to_wire(binary() | nil) :: %{time: map() | nil, scope: map() | nil}
  def to_wire(json) do
    defaults = decode(json)
    %{time: time(defaults["time"]), scope: scope(defaults["scope"])}
  end

  @doc "The stored JSON after applying the wire `defaults` (absent: unchanged)."
  @spec to_stored(binary() | nil, term()) :: {:ok, binary()} | {:error, term()}
  def to_stored(json, nil), do: {:ok, json || "{}"}

  def to_stored(json, %{} = wire) do
    defaults = decode(json)

    with {:ok, defaults} <- put_time(defaults, Map.fetch(wire, "time")),
         {:ok, defaults} <- put_scope(defaults, Map.fetch(wire, "scope")),
         :ok <- AuthoringDefaults.validate(defaults),
         {:ok, encoded} <- AuthoringDefaults.encode(defaults) do
      {:ok, encoded}
    else
      {:error, {:invalid_params, _details}} = error -> error
      _invalid -> invalid("isn't a valid range and scope")
    end
  end

  def to_stored(_json, _wire), do: invalid("must be {time, scope}")

  defp time(%{"mode" => "live", "window_seconds" => seconds})
       when is_integer(seconds) and seconds > 0,
       do: %{mode: "relative", range: "now-" <> unit(seconds)}

  defp time(%{"mode" => "range", "from" => "now-" <> _ = from}),
    do: %{mode: "relative", range: from}

  defp time(%{"mode" => "range", "from" => from, "to" => to})
       when is_binary(from) and is_binary(to),
       do: %{mode: "absolute", from: from, to: to}

  defp time(_other), do: nil

  defp scope(%{"spacecraft_id" => id}) when is_binary(id), do: %{mode: "fixed", spacecraft_id: id}
  defp scope(_other), do: nil

  defp put_time(defaults, :error), do: {:ok, defaults}
  defp put_time(defaults, {:ok, nil}), do: {:ok, Map.delete(defaults, "time")}

  defp put_time(defaults, {:ok, %{"mode" => "relative", "range" => range}})
       when is_binary(range) do
    case TimeRange.resolve(range, "now", DateTime.utc_now()) do
      {:ok, {:sliding, seconds}} ->
        time = %{"mode" => "live", "window_seconds" => seconds}
        {:ok, Map.put(defaults, "time", kept(defaults, time))}

      _invalid ->
        invalid("time.range must be like now-6h")
    end
  end

  defp put_time(defaults, {:ok, %{"mode" => "absolute", "from" => from, "to" => to}})
       when is_binary(from) and is_binary(to) do
    with {:ok, a, _} <- DateTime.from_iso8601(from),
         {:ok, b, _} <- DateTime.from_iso8601(to),
         :lt <- DateTime.compare(a, b) do
      {:ok,
       Map.put(defaults, "time", kept(defaults, %{"mode" => "range", "from" => from, "to" => to}))}
    else
      _invalid -> invalid("time.from must be before time.to (ISO 8601)")
    end
  end

  defp put_time(_defaults, _time), do: invalid("time must be relative, absolute or null")

  defp put_scope(defaults, :error), do: {:ok, defaults}
  defp put_scope(defaults, {:ok, nil}), do: {:ok, Map.delete(defaults, "scope")}

  defp put_scope(defaults, {:ok, %{"mode" => mode}}) when mode in ["context", "fleet"],
    do: {:ok, Map.delete(defaults, "scope")}

  defp put_scope(defaults, {:ok, %{"mode" => "fixed", "spacecraft_id" => id}})
       when is_binary(id) and byte_size(id) in 1..256,
       do:
         {:ok,
          Map.put(defaults, "scope", %{
            "primary" => %{"kind" => "spacecraft", "mode" => "one", "ids" => [id]},
            "spacecraft_id" => id
          })}

  defp put_scope(_defaults, _scope),
    do: invalid("scope must be context, fixed (with spacecraft_id), fleet or null")

  defp kept(defaults, time), do: Map.merge(Map.take(defaults["time"] || %{}, ["axis"]), time)

  defp decode(json) when is_binary(json) do
    case AuthoringDefaults.decode(json) do
      {:ok, defaults} -> defaults
      _invalid -> %{}
    end
  end

  defp decode(_none), do: %{}

  defp unit(seconds) do
    {size, suffix} = Enum.find(@units, fn {size, _suffix} -> rem(seconds, size) == 0 end)
    "#{div(seconds, size)}#{suffix}"
  end

  defp invalid(message), do: {:error, {:invalid_params, %{defaults: message}}}
end
