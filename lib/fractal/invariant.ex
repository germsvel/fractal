defmodule Fractal.Invariant do
  @moduledoc """
  App-defined invariants: the app's additions to the verification
  contract.

  An invariant is a property that must be guaranteed **for every page**.
  The framework's own checks in `Fractal.Verify` are universal
  invariants it can state without knowing what your app is; this module
  lets the app add its own — defined once, in one well-known place, and
  run by `mix fractal.verify` against all pages uniformly:

      # lib/fractal/invariants.ex
      defmodule Fractal.Invariants do
        use Fractal.Invariant

        invariant "title fits in a search result", %{page: page} do
          if String.length(page.title()) <= 60,
            do: :ok,
            else: {:error, "title is \#{String.length(page.title())} chars — keep it under 60"}
        end

        invariant "every page links home", %{rendered: rendered} do
          if rendered =~ ~s(href="/"), do: :ok, else: {:error, "add a link back to /"}
        end
      end

  ## The rules

    * The context arrives as an explicit pattern-matched argument
      (ExUnit-style): `%{page: module, rendered: html}`, where
      `rendered` comes from the same empty-assigns smoke render as the
      framework's render check. Omit the pattern when unneeded.
    * Blocks return `:ok` or `{:error, message}`. A crashing invariant
      is a failing one (fail closed).
    * Invariants are read-only observations over all pages. They are
      NOT per-page verification — a page's behavioral spec is its test
      file — and pages have no verification API of their own.
    * `mix fractal.ai.docs` prints the invariant inventory, so agents
      learn the house rules before writing a page.
    * Invariants apply uniformly; there is no per-invariant page
      filtering. An invariant that doesn't apply to a page can return
      `:ok` for it, keeping the judgment visible in its body.
  """

  @callback run(name :: String.t(), context :: map()) :: :ok | {:error, String.t()}

  @optional_callbacks run: 2

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      if opts != [] do
        raise ArgumentError, "use Fractal.Invariant takes no options"
      end

      @behaviour Fractal.Invariant

      import Fractal.Invariant, only: [invariant: 2, invariant: 3]

      Module.register_attribute(__MODULE__, :fractal_invariant_names, accumulate: true)

      @before_compile Fractal.Invariant
    end
  end

  @doc """
  Defines a named invariant. The context (`%{page: module,
  rendered: html}`) arrives as an explicit pattern-matched argument;
  the block returns `:ok` or `{:error, message}`.
  """
  defmacro invariant(name, do: block) when is_binary(name) do
    quote do
      @fractal_invariant_names unquote(name)

      def run(unquote(name), _invariant_context), do: unquote(block)
    end
  end

  defmacro invariant(name, pattern, do: block) when is_binary(name) do
    quote do
      @fractal_invariant_names unquote(name)

      def run(unquote(name), unquote(pattern) = _invariant_context), do: unquote(block)
    end
  end

  defmacro __before_compile__(env) do
    invariants =
      env.module
      |> Module.get_attribute(:fractal_invariant_names)
      |> Enum.reverse()

    if Enum.uniq(invariants) != invariants do
      raise ArgumentError,
            "#{inspect(env.module)} defines duplicate invariants: #{inspect(invariants)}"
    end

    quote do
      @doc false
      def __fractal_invariants__, do: unquote(invariants)
    end
  end

  # -- discovery ----------------------------------------------------------

  @doc "The app's invariants module, or `nil` (there should be at most one)."
  @spec module() :: module() | nil
  def module, do: modules() |> List.first()

  @doc false
  @spec modules() :: [module()]
  def modules do
    Fractal.Discovery.modules()
    |> Enum.filter(&invariant_module?/1)
    |> Enum.sort_by(&inspect/1)
  end

  @doc "Returns `true` if `module` is a compiled invariants module."
  @spec invariant_module?(module()) :: boolean()
  def invariant_module?(module) do
    Code.ensure_loaded?(module) and
      function_exported?(module, :__fractal_invariants__, 0) and
      __MODULE__ in behaviours(module)
  end

  @doc "The names of all defined invariants."
  @spec names() :: [String.t()]
  def names do
    case module() do
      nil -> []
      mod -> mod.__fractal_invariants__()
    end
  end

  @doc """
  Runs the named invariant against a context. Raises when no invariants
  module exists (fail closed; `Fractal.Verify` only calls this for
  names it discovered).
  """
  @spec run(String.t(), map()) :: :ok | {:error, String.t()}
  def run(name, context) do
    mod = module() || raise "no invariants module exists — nothing defines #{inspect(name)}"
    mod.run(name, context)
  end

  defp behaviours(module) do
    module.module_info(:attributes)
    |> Keyword.get_values(:behaviour)
    |> List.flatten()
  end
end
