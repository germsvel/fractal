defmodule Fractal.Bus do
  @moduledoc false

  # The internal seam over the pub/sub backend (currently Phoenix.PubSub,
  # supervised by Fractal.Application). Apps never touch this module —
  # their surface is `publish/1` (imported into pages via
  # Fractal.Interactive) and the page-level `watch:` declaration. Keeping
  # the backend behind this seam means it can become Registry or Postgres
  # LISTEN/NOTIFY without any app code changing.
  #
  # Topics are path-shaped ("rooms/:id/messages"), and messages carry no
  # payload — a publish is a doorbell. Subscribers re-render from the
  # database, which is what keeps missed messages free and the backend
  # swappable.

  @pubsub Fractal.Bus.PubSub

  @doc false
  def child_spec(_opts), do: Phoenix.PubSub.child_spec(name: @pubsub)

  @doc false
  def subscribe(topic) when is_binary(topic) do
    Phoenix.PubSub.subscribe(@pubsub, topic)
  end

  @doc false
  # named broadcast (not publish) so the verify topology scan, which
  # looks for publish(...) calls in app sources, never matches the
  # framework's own delegation
  def broadcast(topic) when is_binary(topic) do
    Phoenix.PubSub.broadcast(@pubsub, topic, {:fractal_watch, topic})
    :ok
  end

  @doc false
  # A valid topic pattern: path-shaped segments without a leading slash.
  # Segments are literals or `:name` params, same vocabulary as routes.
  def valid_topic?(topic) do
    is_binary(topic) and topic != "" and
      not String.starts_with?(topic, "/") and
      not String.ends_with?(topic, "/") and
      not String.contains?(topic, "//") and
      Fractal.Page.route?("/" <> topic)
  end

  @doc false
  # A concrete (publishable/subscribable) topic: no unbound params left.
  def concrete_topic?(topic) do
    valid_topic?(topic) and topic_params(topic) == []
  end

  @doc false
  # The `:name` params a topic pattern binds.
  def topic_params(topic) do
    for ":" <> name <- segments(topic), do: name
  end

  @doc false
  # Resolves a topic pattern against params: "rooms/:id/messages" with
  # %{"id" => "42"} → "rooms/42/messages".
  def resolve(topic, params) do
    topic
    |> segments()
    |> Enum.map_join("/", fn
      ":" <> name -> to_string(Map.fetch!(params, name))
      literal -> literal
    end)
  end

  defp segments(topic), do: topic |> String.split("/") |> Enum.reject(&(&1 == ""))
end
