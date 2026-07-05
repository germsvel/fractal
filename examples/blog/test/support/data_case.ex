defmodule Blog.DataCase do
  @moduledoc """
  Test case template for tests that touch the database.

      use Blog.DataCase, async: true

  Each test runs inside an `Ecto.Adapters.SQL.Sandbox` transaction that
  rolls back afterwards, so tests are isolated and can run concurrently.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias Blog.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Blog.DataCase
    end
  end

  setup tags do
    Blog.DataCase.setup_sandbox(tags)
    :ok
  end

  @doc "Checks out a sandbox connection owned by the test process."
  def setup_sandbox(tags) do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Blog.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
  end
end
