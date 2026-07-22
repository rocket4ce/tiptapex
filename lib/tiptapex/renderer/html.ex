defmodule Tiptapex.Renderer.HTML do
  @moduledoc """
  Safe HTML building blocks for `Tiptapex.Renderer`.

  Every attribute value passes through `Phoenix.HTML.attributes_escape/1`
  and every text chunk through `Phoenix.HTML.html_escape/1` — nothing is
  ever string-interpolated into markup. All functions return iodata; the
  renderer wraps the final result in `{:safe, iodata}`.
  """

  @doc """
  Builds `<name attrs>children</name>` as iodata.

  Attribute values that are `nil`, `false`, or `""` are dropped.
  """
  @spec tag(binary(), Enumerable.t(), iodata()) :: iodata()
  def tag(name, attrs, children) do
    ["<", name, escape_attrs(attrs), ">", children, "</", name, ">"]
  end

  @doc "Builds a void element `<name attrs>` as iodata."
  @spec void_tag(binary(), Enumerable.t()) :: iodata()
  def void_tag(name, attrs) do
    ["<", name, escape_attrs(attrs), ">"]
  end

  @doc "Escapes a text chunk, returning iodata."
  @spec escape(term()) :: iodata()
  def escape(nil), do: ""

  def escape(text) do
    {:safe, io} = Phoenix.HTML.html_escape(to_string(text))
    io
  end

  @doc """
  Joins `property: value` pairs into a style attribute value, skipping
  blank entries. Returns `nil` when nothing remains so the attribute is
  dropped entirely.
  """
  @spec style([{binary(), binary() | nil}]) :: binary() | nil
  def style(pairs) do
    case for {prop, value} <- pairs, value not in [nil, ""], do: [prop, ": ", value] do
      [] -> nil
      declarations -> declarations |> Enum.intersperse("; ") |> IO.iodata_to_binary()
    end
  end

  defp escape_attrs(attrs) do
    attrs =
      for {key, value} <- attrs, value not in [nil, false, ""], do: {key, value}

    case attrs do
      [] ->
        ""

      attrs ->
        {:safe, io} = Phoenix.HTML.attributes_escape(attrs)
        io
    end
  end
end
