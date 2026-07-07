defmodule Fractal.Checkpoint do
  @moduledoc """
  Cross-cutting request behavior: guards, expectations, and context.

  Fractal deliberately has **no middleware**. An ordered stack of opaque
  functions acting at a distance is the antithesis of "read one page
  file, understand the route" — ordering bugs, silent request mutation,
  and forgotten coverage are the classic failure modes. Instead,
  cross-cutting behavior is *declared where it applies, defined in one
  well-known place, and guaranteed by verification*:

      # the page says it — visible in the one file that matters
      use Fractal.Page, path: "/admin", title: "Admin", require: :signed_in

      # lib/my_app/checkpoints.ex — the ONE module defining what names mean
      defmodule MyApp.Checkpoints do
        use Fractal.Checkpoint

        def context(assigns) do
          %{"user_name" => assigns.session["user_name"]}
        end

        guard :signed_in, %{context: context} do
          if context["user_name"],
            do: :ok,
            else: {:redirect, "/login", flash: %{"error" => "Please log in first."}}
        end

        expect "/admin", :signed_in
      end

  ## Guards

  `guard name, pattern do ... end` defines a named check. The assigns
  (params, session, path, context — same shape pages see) arrive as an
  explicit pattern-matched argument, ExUnit-style; the block
  must return `:ok` or `{:redirect, to}` / `{:redirect, to, directives}`
  — the same vocabulary as page handlers. Guards cannot mutate assigns:
  they allow or redirect, nothing else. Unlike components, guards may
  query the database.

  Pages declare guards with the `require:` option; they run in declared
  order before `render/1`, every `handle_*/1`, **and interactive
  events** — events dispatch to a page, so they cannot bypass its
  guards.

  ## Expectations

  `expect "/admin", :signed_in` does not change runtime behavior — it
  makes `mix fractal.verify` fail any page whose path lives under
  `/admin` without `require: :signed_in`, naming the page. Coverage is
  guaranteed mechanically; each page still shows its own guards.

  ## Context

  Override `context/1` to derive request-scoped data (the current user,
  a locale) once; it lands under `assigns.context` for every page and
  guard. Identity-scale derivation only — it must tolerate an empty
  session, and business logic belongs in pages.
  """

  @callback check(name :: atom(), assigns :: map()) ::
              :ok | {:redirect, String.t()} | {:redirect, String.t(), keyword()}
  @callback context(assigns :: map()) :: map()

  @optional_callbacks check: 2, context: 1

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      if opts != [] do
        raise ArgumentError, "use Fractal.Checkpoint takes no options"
      end

      @behaviour Fractal.Checkpoint

      import Fractal.Checkpoint, only: [guard: 2, guard: 3, expect: 2]

      Module.register_attribute(__MODULE__, :fractal_guard_names, accumulate: true)
      Module.register_attribute(__MODULE__, :fractal_expectations, accumulate: true)

      @before_compile Fractal.Checkpoint

      def context(_assigns), do: %{}
      defoverridable context: 1
    end
  end

  @doc """
  Defines a named guard. The assigns arrive as an explicit,
  pattern-matched argument (ExUnit-style — no magic variables); the
  block returns `:ok` or `{:redirect, to[, directives]}`.

      guard :signed_in, %{context: context} do
        if context["user_name"], do: :ok, else: {:redirect, "/login"}
      end

  Omit the pattern when the guard needs no assigns.
  """
  defmacro guard(name, do: block) when is_atom(name) do
    quote do
      @fractal_guard_names unquote(name)

      def check(unquote(name), _guard_assigns), do: unquote(block)
    end
  end

  defmacro guard(name, pattern, do: block) when is_atom(name) do
    quote do
      @fractal_guard_names unquote(name)

      def check(unquote(name), unquote(pattern) = _guard_assigns), do: unquote(block)
    end
  end

  @doc """
  Declares that every page under `prefix` must `require:` the named
  guard. Enforced by `mix fractal.verify`, not at runtime.
  """
  defmacro expect(prefix, guard_name) do
    quote do
      @fractal_expectations {unquote(prefix), unquote(guard_name)}
    end
  end

  defmacro __before_compile__(env) do
    guards =
      env.module
      |> Module.get_attribute(:fractal_guard_names)
      |> Enum.reverse()

    expectations =
      env.module
      |> Module.get_attribute(:fractal_expectations)
      |> Enum.reverse()

    if Enum.uniq(guards) != guards do
      raise ArgumentError, "#{inspect(env.module)} defines duplicate guards: #{inspect(guards)}"
    end

    for {prefix, name} <- expectations do
      unless is_binary(prefix) and String.starts_with?(prefix, "/") do
        raise ArgumentError,
              "expect prefix must be a path string starting with \"/\", got: #{inspect(prefix)}"
      end

      unless name in guards do
        raise ArgumentError,
              "#{inspect(env.module)} expects #{inspect(name)} under #{inspect(prefix)} " <>
                "but defines no such guard — add `guard #{inspect(name)} do ... end`"
      end
    end

    quote do
      @doc false
      def __fractal_guards__, do: unquote(guards)

      @doc false
      def __fractal_expectations__, do: unquote(Macro.escape(expectations))
    end
  end

  # -- discovery and the runner ------------------------------------------

  @doc "The app's checkpoint module, or `nil` (there should be at most one)."
  @spec module() :: module() | nil
  def module, do: Fractal.Routes.checkpoint()

  @doc false
  @spec modules() :: [module()]
  def modules do
    Fractal.Discovery.modules()
    |> Enum.filter(&checkpoint_module?/1)
    |> Enum.sort_by(&inspect/1)
  end

  @doc "Returns `true` if `module` is a compiled checkpoint module."
  @spec checkpoint_module?(module()) :: boolean()
  def checkpoint_module?(module) do
    Code.ensure_loaded?(module) and
      function_exported?(module, :__fractal_guards__, 0) and
      __MODULE__ in behaviours(module)
  end

  @doc "The names of all defined guards."
  @spec names() :: [atom()]
  def names do
    case module() do
      nil -> []
      mod -> mod.__fractal_guards__()
    end
  end

  @doc "All `expect/2` declarations, as `{prefix, guard_name}` tuples."
  @spec expectations() :: [{String.t(), atom()}]
  def expectations do
    case module() do
      nil -> []
      mod -> mod.__fractal_expectations__()
    end
  end

  @doc "The app-defined request context (empty when no checkpoint module exists)."
  @spec context(map()) :: map()
  def context(assigns) do
    case module() do
      nil -> %{}
      mod -> mod.context(assigns)
    end
  end

  @doc """
  Runs the named guards in order; the first non-`:ok` result wins.

  Returns `:ok` or `{:redirect, to, directives}`. Raises when a guard
  is undefined or a checkpoint module is missing — a page requiring guards
  fails closed, never open (verification catches this before runtime).
  """
  @spec run([atom()], map()) :: :ok | {:redirect, String.t(), keyword()}
  def run([], _assigns), do: :ok

  def run(names, assigns) do
    mod =
      module() ||
        raise "pages require guards #{inspect(names)} but there is no checkpoint module — " <>
                "create lib/my_app/checkpoints.ex with `use Fractal.Checkpoint`"

    Enum.reduce_while(names, :ok, fn name, :ok ->
      case mod.check(name, assigns) do
        :ok ->
          {:cont, :ok}

        {:redirect, to} when is_binary(to) ->
          {:halt, denied(name, to, [], assigns)}

        {:redirect, to, directives} when is_binary(to) and is_list(directives) ->
          {:halt, denied(name, to, directives, assigns)}

        other ->
          raise ArgumentError,
                "guard #{inspect(name)} must return :ok or {:redirect, to[, directives]}, " <>
                  "got: #{inspect(other)}"
      end
    end)
  end

  defp denied(name, to, directives, assigns) do
    :telemetry.execute([:fractal, :checkpoint, :denied], %{count: 1}, %{
      guard: name,
      path: assigns[:path]
    })

    {:redirect, to, directives}
  end

  @doc "Matches a path against an expectation prefix, segment-aware."
  @spec under?(String.t(), String.t()) :: boolean()
  def under?(path, prefix) do
    path == prefix or String.starts_with?(path, prefix <> "/")
  end

  defp behaviours(module) do
    module.module_info(:attributes)
    |> Keyword.get_values(:behaviour)
    |> List.flatten()
  end
end
