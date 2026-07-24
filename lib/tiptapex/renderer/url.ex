defmodule Tiptapex.Renderer.URL do
  @moduledoc """
  URL and CSS value sanitization for `Tiptapex.Renderer`.

  These allow-lists are the core XSS defense: link/image/video URLs must be
  http(s), mailto, or relative; iframes are only ever emitted for canonical
  YouTube embed URLs rebuilt from a validated video id; CSS values must
  match a strict grammar that cannot break out of a style attribute.
  """

  @allowed_schemes ~w(http https mailto)
  @data_image ~r{^data:image/(png|jpe?g|gif|webp|svg\+xml)[;,]}i

  @doc """
  Validates a user-supplied URL for href/src attributes.

  Accepts absolute http/https/mailto URLs, protocol-relative URLs, and
  relative paths/fragments. Rejects everything else — notably
  `javascript:`, `vbscript:`, and `data:` — plus anything containing
  control characters.
  """
  @spec safe_url(term()) :: {:ok, binary()} | :error
  def safe_url(url) when is_binary(url) do
    url = String.trim(url)

    cond do
      url == "" -> :error
      String.match?(url, ~r/[\x00-\x1f\x7f]/) -> :error
      true -> check_scheme(url)
    end
  end

  def safe_url(_), do: :error

  defp check_scheme(url) do
    case URI.parse(url) do
      %URI{scheme: nil} ->
        {:ok, url}

      %URI{scheme: scheme} ->
        if String.downcase(scheme) in @allowed_schemes, do: {:ok, url}, else: :error
    end
  end

  @doc """
  Validates a URL for an `img` `src`.

  Everything `safe_url/1` accepts, plus `data:` URIs for images — which
  `safe_url/1` rejects (a `data:` link is a navigation vector, but a `data:`
  image is inert, and it is the only src Chrome can resolve inside a PDF
  running header). SVG is included: an SVG loaded through `<img>` cannot run
  scripts, which is the only way these are ever rendered.
  """
  @spec safe_image_url(term()) :: {:ok, binary()} | :error
  def safe_image_url(url) when is_binary(url) do
    trimmed = String.trim(url)

    cond do
      trimmed == "" -> :error
      String.match?(trimmed, ~r/[\x00-\x1f\x7f]/) -> :error
      Regex.match?(@data_image, trimmed) -> {:ok, trimmed}
      true -> safe_url(trimmed)
    end
  end

  def safe_image_url(_), do: :error

  @doc """
  Normalizes any of the common YouTube URL shapes to the canonical embed
  URL, validating the video id. This is the ONLY URL ever placed in an
  iframe `src`; anything that doesn't resolve here drops the whole node.

  Mirrors `toYoutubeEmbed/1` in `assets/js/tiptapex/extensions/video.js`,
  but rebuilds the URL from the extracted id instead of passing the
  original through.
  """
  @spec youtube_embed(term()) :: {:ok, binary()} | :error
  def youtube_embed(url) when is_binary(url) do
    uri = URI.parse(String.trim(url))
    host = (uri.host || "") |> String.downcase() |> String.replace_prefix("www.", "")
    path = uri.path || ""

    id =
      cond do
        host == "youtu.be" -> String.trim_leading(path, "/")
        host == "youtube.com" or String.ends_with?(host, ".youtube.com") -> youtube_id(uri, path)
        true -> nil
      end

    if is_binary(id) and id =~ ~r/^[A-Za-z0-9_-]{5,20}$/ do
      {:ok, "https://www.youtube.com/embed/" <> id}
    else
      :error
    end
  end

  def youtube_embed(_), do: :error

  defp youtube_id(uri, path) do
    cond do
      String.starts_with?(path, "/embed/") ->
        path |> String.trim_leading("/embed/") |> String.split("/") |> hd()

      path == "/watch" ->
        (uri.query || "") |> URI.decode_query() |> Map.get("v")

      String.starts_with?(path, "/shorts/") ->
        path |> String.trim_leading("/shorts/") |> String.split("/") |> hd()

      true ->
        nil
    end
  end

  # Simple values: hex colors, keywords, sizes, unquoted font stacks.
  @plain_css ~r/^[A-Za-z0-9#,.\s%_-]+$/
  # Functional color notation with strictly numeric arguments.
  @color_fn ~r/^(?:rgb|rgba|hsl|hsla)\(\s*\d{1,3}(?:\s*,\s*\d{1,3}(?:\.\d+)?%?){1,3}(?:\s*,\s*(?:0|1|0?\.\d+))?\s*\)$/i

  @doc """
  Validates a CSS value for inline style emission (colors, font sizes,
  font families, line heights). The grammar admits no `;`, braces, quotes,
  `url(`, or escapes, so a value can never break out of its declaration.
  """
  @spec safe_css_value(term()) :: {:ok, binary()} | :error
  def safe_css_value(value) when is_number(value), do: {:ok, to_string(value)}

  def safe_css_value(value) when is_binary(value) do
    value = String.trim(value)

    cond do
      value == "" -> :error
      String.length(value) > 100 -> :error
      Regex.match?(@plain_css, value) -> {:ok, value}
      Regex.match?(@color_fn, value) -> {:ok, value}
      true -> :error
    end
  end

  def safe_css_value(_), do: :error

  @doc "Coerces a width attribute to integer pixels."
  @spec int_width(term()) :: {:ok, pos_integer()} | :error
  def int_width(value) when is_integer(value) and value > 0, do: {:ok, value}
  def int_width(value) when is_float(value) and value > 0, do: {:ok, round(value)}

  def int_width(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, rest} when int > 0 and rest in ["", "px"] -> {:ok, int}
      _ -> :error
    end
  end

  def int_width(_), do: :error

  @doc "Validates a text-align value."
  @spec text_align(term()) :: {:ok, binary()} | :error
  def text_align(value) when value in ~w(left center right justify), do: {:ok, value}
  def text_align(_), do: :error
end
