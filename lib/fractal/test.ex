defmodule Fractal.Test do
  @moduledoc """
  Test helpers for exercising pages through `Fractal.Router`.

      import Fractal.Test

      test "creates and redirects" do
        conn = post("/posts", %{"title" => "Hi"})
        assert conn.status == 303
      end

  The helpers handle the plumbing pages never see: they mark the conn as
  CSRF-exempt (Plug's own `:plug_skip_csrf_protection` escape hatch — the
  protection itself is covered by framework tests) and give every request
  a test session, so no cookie round-trips are needed.

  Seed a session for logged-in scenarios with the `:session` option:

      conn = get("/dashboard", %{}, session: %{"user_id" => user.id})

  Assert on session changes with `Plug.Conn.get_session/2` on the
  returned conn:

      conn = post("/login", %{"name" => "Ada"})
      assert Plug.Conn.get_session(conn, "user_name") == "Ada"
  """

  import Plug.Test, only: [conn: 3, init_test_session: 2]

  alias Fractal.Router

  @doc "GETs a page through the router."
  @spec get(String.t(), map(), keyword()) :: Plug.Conn.t()
  def get(path, params \\ %{}, opts \\ []), do: request(:get, path, params, opts)

  @doc "POSTs to a page's post route through the router."
  @spec post(String.t(), map(), keyword()) :: Plug.Conn.t()
  def post(path, params \\ %{}, opts \\ []), do: request(:post, path, params, opts)

  @doc "PUTs to a page's put route through the router."
  @spec put(String.t(), map(), keyword()) :: Plug.Conn.t()
  def put(path, params \\ %{}, opts \\ []), do: request(:put, path, params, opts)

  @doc "PATCHes a page — dispatches to its put route, like PUT."
  @spec patch(String.t(), map(), keyword()) :: Plug.Conn.t()
  def patch(path, params \\ %{}, opts \\ []), do: request(:patch, path, params, opts)

  @doc "DELETEs to a page's delete route through the router."
  @spec delete(String.t(), map(), keyword()) :: Plug.Conn.t()
  def delete(path, params \\ %{}, opts \\ []), do: request(:delete, path, params, opts)

  @doc """
  Fires an interactive event at the page serving `path`, exactly as the
  browser runtime would.

      conn = fire_event("/counter", "increment", %{"count" => "0"})
  """
  @spec fire_event(String.t(), String.t(), map(), keyword()) :: Plug.Conn.t()
  def fire_event(path, event, values \\ %{}, opts \\ []) do
    params = Map.merge(%{"_fx_path" => path, "_fx_event" => event}, values)
    request(:post, "/fractal/event", params, opts)
  end

  @doc """
  Delivers a watch topic to the page serving `path`, exactly as a
  `publish/1` would over the push stream — resolve the page, run its
  guards, run `handle_watch/2` — and returns the response: 200 with the
  fragment, 204 with an `fx-redirect` header, or 303 when a guard
  denies.

      conn = fire_watch("/rooms/42", "rooms/:id/messages")
      assert conn.resp_body =~ "the new message"

  Pass the topic as the page declares it (the pattern, not a resolved
  instance).
  """
  @spec fire_watch(String.t(), String.t(), keyword()) :: Plug.Conn.t()
  def fire_watch(path, topic, opts \\ []) do
    :get
    |> conn(path, %{})
    |> init_test_session(opts[:session] || %{})
    |> Plug.Conn.put_private(:plug_skip_csrf_protection, true)
    |> Router.fire_watch(topic)
  end

  defp request(method, path, params, opts) do
    method
    |> conn(path, params)
    |> init_test_session(opts[:session] || %{})
    |> Plug.Conn.put_private(:plug_skip_csrf_protection, true)
    |> Router.call([])
  end
end
