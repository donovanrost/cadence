defmodule Cadence.Platform.SaveTrail do
  @moduledoc """
  Who saved a limit or derived-telemetry definition version, and through which path (director,
  2026-11-16; DECISIONS #77/#93, sweep row 3). Stored in the new version's metadata:

    * `"saved_by"`: the actor, `Scope.audit_actor/1`'s `%{"kind", "id"}`;
    * `"via"`: `"console"`, `"legacy_host"` or `"change_set"`.

  Time is the version's own `inserted_at`; before and after are the previous and the new
  immutable version, so nothing else is copied here.

  The trail is informational: `without/1` strips it before any content comparison (a retried or
  raced save of the same version, a change set's document), so it never mints a version or shows
  as a change.
  """

  @keys ["saved_by", "via"]
  @vias ["console", "legacy_host", "change_set"]

  @spec put(map() | nil, map(), binary()) :: map()
  def put(metadata, %{"kind" => kind, "id" => id}, via)
      when is_binary(kind) and via in @vias,
      do: Map.merge(metadata || %{}, %{"saved_by" => %{"kind" => kind, "id" => id}, "via" => via})

  @doc """
  A change set's write: `via` only. Its actor is the change set's own (`applied_by` on the
  configuration revision it applied), which the kinds aren't given; an older trail is dropped.
  """
  @spec change_set(map() | nil) :: map()
  def change_set(metadata), do: metadata |> without() |> Map.put("via", "change_set")

  @doc "`metadata` without the trail (string or atom keys)."
  @spec without(map() | nil) :: map()
  def without(nil), do: %{}

  def without(metadata) when is_map(metadata),
    do: Map.drop(metadata, @keys ++ [:saved_by, :via])
end
