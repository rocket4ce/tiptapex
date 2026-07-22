defmodule Tiptapex.Renderer.Marks do
  @moduledoc """
  Built-in mark renderers for `Tiptapex.Renderer`.

  Marks wrap a text node's escaped content in nested inline tags. Nesting
  order is deterministic (link outermost … bold innermost) so identical
  documents always produce identical HTML.
  """

  alias Tiptapex.Renderer.{HTML, URL}

  # Outermost → innermost. Unknown/custom marks wrap outside `link`.
  @order ~w(link textStyle highlight code strike underline italic bold)

  @doc "Nesting order, outermost first."
  def order, do: @order

  @doc """
  Wraps `children` in one mark. Returns `{:ok, iodata}` or `:unknown`.

  A mark whose attributes fail sanitization degrades gracefully: the tag is
  emitted without the offending attribute (or, for `textStyle` with no
  valid styles left, the children pass through unwrapped).
  """
  @spec render(binary(), map(), iodata(), map()) :: {:ok, iodata()} | :unknown
  def render(type, mark, children, opts)

  def render("bold", _mark, children, _opts), do: {:ok, HTML.tag("strong", [], children)}
  def render("italic", _mark, children, _opts), do: {:ok, HTML.tag("em", [], children)}
  def render("underline", _mark, children, _opts), do: {:ok, HTML.tag("u", [], children)}
  def render("strike", _mark, children, _opts), do: {:ok, HTML.tag("s", [], children)}
  def render("code", _mark, children, _opts), do: {:ok, HTML.tag("code", [], children)}

  def render("link", mark, children, _opts) do
    a = attrs(mark)

    case URL.safe_url(a["href"]) do
      {:ok, href} ->
        target = if a["target"] == "_blank", do: "_blank"

        {:ok,
         HTML.tag(
           "a",
           [{"href", href}, {"target", target}, {"rel", "noopener nofollow"}],
           children
         )}

      :error ->
        # Unsafe href: keep the text, lose the link.
        {:ok, children}
    end
  end

  def render("highlight", mark, children, _opts) do
    case URL.safe_css_value(attrs(mark)["color"]) do
      {:ok, color} ->
        {:ok,
         HTML.tag(
           "mark",
           [{"data-color", color}, {"style", "background-color: #{color}"}],
           children
         )}

      :error ->
        {:ok, HTML.tag("mark", [], children)}
    end
  end

  def render("textStyle", mark, children, _opts) do
    a = attrs(mark)

    style =
      HTML.style([
        {"color", css(a["color"])},
        {"background-color", css(a["backgroundColor"])},
        {"font-size", css(a["fontSize"])},
        {"font-family", css(a["fontFamily"])}
      ])

    if style do
      {:ok, HTML.tag("span", [{"style", style}], children)}
    else
      {:ok, children}
    end
  end

  def render(_type, _mark, _children, _opts), do: :unknown

  defp css(value) do
    case URL.safe_css_value(value) do
      {:ok, v} -> v
      :error -> nil
    end
  end

  defp attrs(%{"attrs" => %{} = attrs}), do: attrs
  defp attrs(_), do: %{}
end
