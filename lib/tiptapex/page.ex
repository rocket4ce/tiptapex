defmodule Tiptapex.Page do
  @moduledoc """
  Page setup for paginated documents: paper size, orientation, margins,
  running headers/footers and page numbering.

  The canonical home for this configuration is the document itself — the
  ProseMirror `doc` node carries it under `attrs.page`:

      %{
        "type" => "doc",
        "attrs" => %{
          "page" => %{
            "size" => "letter",
            "orientation" => "portrait",
            "margins" => %{"top" => 25.4, "right" => 25.4, "bottom" => 25.4, "left" => 25.4},
            "header" => %{"left" => "Acme S.A.", "center" => "", "right" => "{date}"},
            "footer" => %{"left" => "", "center" => "", "right" => ""},
            "numbering" => %{
              "enabled" => true,
              "region" => "footer",
              "align" => "center",
              "format" => "Page {page} of {pages}"
            }
          }
        },
        "content" => [...]
      }

  A document without `attrs.page` is not paginated — the editor renders the
  usual continuous surface and `Tiptapex.Export.PDF` falls back to A4-ish
  defaults only if you ask for them explicitly.

  ## Sizes

  Presets (millimetres, portrait):

  #{Enum.map_join([letter: "215.9 × 279.4 (8.5 × 11 in)", legal: "215.9 × 355.6 (8.5 × 14 in)", tabloid: "279.4 × 431.8 (11 × 17 in)", executive: "184.15 × 266.7 (7.25 × 10.5 in)", a3: "297 × 420", a4: "210 × 297", a5: "148 × 210"], "\n", fn {k, v} -> "    * `#{inspect(k)}` — #{v}" end)}

  Anything else is a custom size: `%{width: 200, height: 250}`.

  ## Units

  Lengths are millimetres. Plain numbers are read as mm; strings may carry a
  unit — `"1in"`, `"2.5cm"`, `"72pt"`, `"96px"` (CSS px at 96 dpi).

      Tiptapex.Page.new(%{size: :letter, margins: %{top: "1in", bottom: "1in"}})

  ## Headers and footers

  Each region has three slots — `:left`, `:center`, `:right` — holding text
  and/or an image (a logo). Text supports tokens:

    * `{page}` — current page number
    * `{pages}` — total pages
    * `{date}` — print date
    * `{time}` — print time
    * `{title}` — the document title (`:title`, or the `<title>` of the
      exported HTML)

  This maps 1:1 onto what both supported PDF engines can do natively, so page
  numbers are produced by the engine and are always correct — see
  `Tiptapex.Export.PDF`.

  Page numbering is a convenience on top: enabling it drops `:format` into the
  slot named by `:align` of the region named by `:region`, unless that slot
  already contains a `{page}` token.

  ## Logos

  A slot is either a plain string (text only) or a map:

      header: %{
        left: %{image: %{src: "/uploads/logo.png", height: 12}},
        center: "",
        right: "{page} / {pages}"
      }

  `:height` is millimetres (default 8, clamped to 100) and the width
  follows the image's aspect ratio. `:src` must be http(s), a relative path,
  or a `data:` URI for a raster image or SVG — anything else is dropped, the
  same allow-list discipline `Tiptapex.Renderer` applies to the document.

  Normalised slots are always `%{text: binary, image: map | nil}`;
  `to_map/1` writes the compact string form back out when a slot carries no
  image, so documents without logos keep the JSON they had.

  > #### Chrome cannot resolve relative logo URLs {: .warning}
  >
  > ChromicPDF renders the running header/footer in a context with no base
  > URL, so `/uploads/logo.png` will not load. Give the logo an absolute URL,
  > or pass `:asset_url` to `Tiptapex.Export.PDF` to rewrite it (typically
  > into a `data:` URI).
  """

  @typedoc "A logo in a header/footer slot. `:height` is millimetres."
  @type image :: %{src: String.t(), alt: String.t(), height: float()}

  @typedoc "One header/footer slot: text, an image, or both."
  @type slot :: %{text: String.t(), image: image() | nil}

  @typedoc "A header/footer region: three slots."
  @type region :: %{left: slot(), center: slot(), right: slot()}

  @typedoc "Millimetre lengths per side."
  @type margins :: %{top: float(), right: float(), bottom: float(), left: float()}

  @type numbering :: %{
          enabled: boolean(),
          region: :header | :footer,
          align: :left | :center | :right,
          format: String.t()
        }

  @type size :: atom() | %{width: float(), height: float()}

  @type t :: %__MODULE__{
          size: size(),
          orientation: :portrait | :landscape,
          margins: margins(),
          header: region(),
          footer: region(),
          numbering: numbering(),
          title: String.t() | nil
        }

  @default_margin 25.4

  defstruct size: :letter,
            orientation: :portrait,
            margins: %{
              top: @default_margin,
              right: @default_margin,
              bottom: @default_margin,
              left: @default_margin
            },
            header: %{
              left: %{text: "", image: nil},
              center: %{text: "", image: nil},
              right: %{text: "", image: nil}
            },
            footer: %{
              left: %{text: "", image: nil},
              center: %{text: "", image: nil},
              right: %{text: "", image: nil}
            },
            numbering: %{enabled: false, region: :footer, align: :center, format: "{page}"},
            title: nil

  # Portrait dimensions in millimetres.
  @presets %{
    letter: {215.9, 279.4},
    legal: {215.9, 355.6},
    tabloid: {279.4, 431.8},
    executive: {184.15, 266.7},
    a3: {297.0, 420.0},
    a4: {210.0, 297.0},
    a5: {148.0, 210.0}
  }

  @slots [:left, :center, :right]
  @default_image_height 8.0
  @max_image_height 100.0
  @tokens ~w(page pages date time title)
  # Header/footer text is user input that ends up in a shell argument
  # (wkhtmltopdf) or an HTML template (Chrome); keep it bounded.
  @max_slot_length 500

  @doc "The built-in paper sizes as `%{name => {width_mm, height_mm}}` (portrait)."
  @spec presets() :: %{atom() => {float(), float()}}
  def presets, do: @presets

  @doc "The built-in paper size names."
  @spec preset_names() :: [atom()]
  def preset_names, do: @presets |> Map.keys() |> Enum.sort()

  @doc """
  Builds a page configuration, accepting string- or atom-keyed maps,
  keyword lists, or an existing struct. Unknown values fall back to the
  defaults rather than raising — the input often comes from a stored
  document.

      iex> page = Tiptapex.Page.new(%{"size" => "legal", "orientation" => "landscape"})
      iex> Tiptapex.Page.dimensions(page)
      %{width: 355.6, height: 215.9}
  """
  @spec new(t() | map() | keyword() | nil | true) :: t()
  def new(attrs \\ %{})

  def new(%__MODULE__{} = page), do: page
  def new(nil), do: %__MODULE__{}
  def new(true), do: %__MODULE__{}
  def new(attrs) when is_list(attrs), do: attrs |> Map.new() |> new()

  def new(%{} = attrs) do
    a = stringify(attrs)

    %__MODULE__{
      size: parse_size(a["size"]),
      orientation: parse_orientation(a["orientation"]),
      margins: parse_margins(a["margins"]),
      header: parse_region(a["header"]),
      footer: parse_region(a["footer"]),
      numbering: parse_numbering(a["numbering"]),
      title: parse_title(a["title"])
    }
  end

  def new(_other), do: %__MODULE__{}

  @doc """
  Reads the page setup carried by a document, or `nil` when it has none.

  `override` decides what wins:

    * `nil` (default) — use whatever the document carries.
    * `false` — no page setup at all, whatever the document says.
    * `true` — force page setup on, using defaults for anything the
      document doesn't specify.
    * a map/keyword/struct — deep-merged over the document's own setup, so
      `page: %{size: :legal}` changes the paper without touching margins.

      Tiptapex.Page.from_doc(article.body)
      Tiptapex.Page.from_doc(article.body, %{orientation: :landscape})
  """
  @spec from_doc(map() | nil, t() | map() | keyword() | boolean() | nil) :: t() | nil
  def from_doc(doc, override \\ nil)

  def from_doc(_doc, false), do: nil
  def from_doc(doc, nil), do: if(attrs = doc_page(doc), do: new(attrs))
  def from_doc(doc, true), do: new(doc_page(doc) || %{})
  def from_doc(_doc, %__MODULE__{} = page), do: page

  def from_doc(doc, override) when is_list(override),
    do: from_doc(doc, Map.new(override))

  def from_doc(doc, %{} = override),
    do: new(deep_merge(stringify(doc_page(doc) || %{}), stringify(override)))

  @doc """
  Stores a page configuration on the document's `doc` node, returning the
  updated document. Passing `nil` removes it (the document stops being
  paginated).

      doc = Tiptapex.Page.put(doc, %{size: :legal, numbering: %{enabled: true}})
  """
  @spec put(map(), t() | map() | keyword() | nil) :: map()
  def put(doc, nil) when is_map(doc) do
    attrs = doc |> fetch_field("attrs") |> stringify_or_empty() |> Map.delete("page")

    if attrs == %{},
      do: drop_field(doc, "attrs"),
      else: put_field(doc, "attrs", attrs)
  end

  def put(doc, page) when is_map(doc) do
    attrs = doc |> fetch_field("attrs") |> stringify_or_empty()
    put_field(doc, "attrs", Map.put(attrs, "page", to_map(new(page))))
  end

  @doc """
  The JSON-encodable form — string keys, millimetres, exactly what the
  `doc` node's `attrs.page` and the editor's `data-ttx-page` carry.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = page) do
    %{
      "size" => size_to_json(page.size),
      "orientation" => Atom.to_string(page.orientation),
      "margins" => Map.new(page.margins, fn {k, v} -> {Atom.to_string(k), v} end),
      "header" => region_to_json(page.header),
      "footer" => region_to_json(page.footer),
      "numbering" => %{
        "enabled" => page.numbering.enabled,
        "region" => Atom.to_string(page.numbering.region),
        "align" => Atom.to_string(page.numbering.align),
        "format" => page.numbering.format
      },
      "title" => page.title
    }
  end

  @doc """
  Paper dimensions in millimetres, with orientation applied.

      iex> Tiptapex.Page.dimensions(Tiptapex.Page.new(%{size: :letter}))
      %{width: 215.9, height: 279.4}
  """
  @spec dimensions(t()) :: %{width: float(), height: float()}
  def dimensions(%__MODULE__{} = page) do
    {w, h} = base_size(page.size)

    case page.orientation do
      :landscape -> %{width: h, height: w}
      _ -> %{width: w, height: h}
    end
  end

  @doc "The printable box — paper minus margins — in millimetres."
  @spec content_box(t()) :: %{width: float(), height: float()}
  def content_box(%__MODULE__{} = page) do
    %{width: w, height: h} = dimensions(page)
    m = page.margins

    %{
      width: max(w - m.left - m.right, 0.0),
      height: max(h - m.top - m.bottom, 0.0)
    }
  end

  @doc """
  The slots of a header/footer region as `[{:left, slot}, {:center, slot},
  {:right, slot}]`, with page numbering merged in. Each slot is
  `%{text: binary, image: map | nil}`.

  Tokens are left untouched — the caller translates them for its engine.
  """
  @spec slots(t(), :header | :footer) :: [{:left | :center | :right, slot()}]
  def slots(%__MODULE__{} = page, region) when region in [:header, :footer] do
    base = Map.fetch!(page, region)
    n = page.numbering

    base =
      if n.enabled and n.region == region do
        Map.update!(base, n.align, fn slot ->
          %{slot | text: merge_numbering(slot.text, n.format)}
        end)
      else
        base
      end

    Enum.map(@slots, &{&1, Map.fetch!(base, &1)})
  end

  defp merge_numbering("", format), do: format

  defp merge_numbering(text, format) do
    if String.contains?(text, "{page}"), do: text, else: text <> " " <> format
  end

  @doc "True when the region has anything to draw."
  @spec region_used?(t(), :header | :footer) :: boolean()
  def region_used?(%__MODULE__{} = page, region) do
    page |> slots(region) |> Enum.any?(fn {_slot, s} -> s.text != "" or s.image != nil end)
  end

  @doc "True when any region of the page carries an image."
  @spec images?(t()) :: boolean()
  def images?(%__MODULE__{} = page) do
    Enum.any?([:header, :footer], fn region ->
      page |> slots(region) |> Enum.any?(fn {_slot, s} -> s.image != nil end)
    end)
  end

  @doc """
  Replaces the `{page}`/`{pages}`/`{date}`/`{time}`/`{title}` tokens in
  `text` using a `%{"page" => ...}` map. Unlisted tokens become `""`.

      iex> Tiptapex.Page.replace_tokens("Page {page} of {pages}", %{"page" => "[page]", "pages" => "[topage]"})
      "Page [page] of [topage]"
  """
  @spec replace_tokens(String.t(), %{optional(String.t()) => String.t()}) :: String.t()
  def replace_tokens(text, replacements) when is_binary(text) do
    Regex.replace(~r/\{(#{Enum.join(@tokens, "|")})\}/, text, fn _match, token ->
      Map.get(replacements, token, "")
    end)
  end

  @doc """
  A CSS `size` value for the `@page` rule, e.g. `"215.9mm 279.4mm"`.
  """
  @spec css_size(t()) :: String.t()
  def css_size(%__MODULE__{} = page) do
    %{width: w, height: h} = dimensions(page)
    "#{mm(w)} #{mm(h)}"
  end

  @doc ~S"""
  A CSS `margin` shorthand value for the `@page` rule, e.g.
  `"25.4mm 25.4mm 25.4mm 25.4mm"`.
  """
  @spec css_margin(t()) :: String.t()
  def css_margin(%__MODULE__{margins: m}) do
    Enum.map_join([m.top, m.right, m.bottom, m.left], " ", &mm/1)
  end

  @doc """
  Millimetres as inches — the unit Chrome's `Page.printToPDF` speaks.

      iex> Tiptapex.Page.to_inches(25.4)
      1.0
  """
  @spec to_inches(number()) :: float()
  def to_inches(mm) when is_number(mm), do: Float.round(mm / 25.4, 6)

  # -------------------------------------------------------------------
  # Parsing
  # -------------------------------------------------------------------

  defp parse_size(nil), do: :letter

  defp parse_size(size) when is_atom(size) do
    if Map.has_key?(@presets, size), do: size, else: :letter
  end

  defp parse_size(size) when is_binary(size) do
    case Enum.find(Map.keys(@presets), &(Atom.to_string(&1) == String.downcase(size))) do
      nil -> :letter
      preset -> preset
    end
  end

  defp parse_size(%{} = size) do
    s = stringify(size)

    with w when is_float(w) <- length_mm(s["width"]),
         h when is_float(h) <- length_mm(s["height"]),
         true <- w > 0 and h > 0 do
      %{width: w, height: h}
    else
      _ -> :letter
    end
  end

  defp parse_size(_), do: :letter

  defp parse_orientation(o) when o in [:landscape, "landscape"], do: :landscape
  defp parse_orientation(_), do: :portrait

  defp parse_margins(nil), do: %__MODULE__{}.margins

  defp parse_margins(%{} = margins) do
    m = stringify(margins)

    Map.new([:top, :right, :bottom, :left], fn side ->
      value =
        case length_mm(m[Atom.to_string(side)]) do
          v when is_float(v) and v >= 0 -> v
          _ -> @default_margin
        end

      {side, value}
    end)
  end

  defp parse_margins(_), do: %__MODULE__{}.margins

  defp parse_region(%{} = region) do
    r = stringify(region)
    Map.new(@slots, &{&1, parse_slot(r[Atom.to_string(&1)])})
  end

  defp parse_region(_), do: empty_region()

  defp empty_region, do: Map.new(@slots, &{&1, %{text: "", image: nil}})

  # A slot is a bare string (text only) or a map carrying text and/or an image.
  defp parse_slot(value) when is_binary(value),
    do: %{text: String.slice(value, 0, @max_slot_length), image: nil}

  defp parse_slot(%{} = value) do
    v = stringify(value)

    text =
      case v["text"] do
        text when is_binary(text) -> String.slice(text, 0, @max_slot_length)
        _ -> ""
      end

    %{text: text, image: parse_image(v["image"])}
  end

  defp parse_slot(_), do: %{text: "", image: nil}

  defp parse_image(%{} = image) do
    i = stringify(image)

    case Tiptapex.Renderer.URL.safe_image_url(i["src"]) do
      {:ok, src} ->
        height =
          case length_mm(i["height"]) do
            value when is_float(value) and value > 0 -> min(value, @max_image_height)
            _ -> @default_image_height
          end

        alt =
          case i["alt"] do
            alt when is_binary(alt) -> String.slice(alt, 0, @max_slot_length)
            _ -> ""
          end

        %{src: src, alt: alt, height: height}

      :error ->
        nil
    end
  end

  defp parse_image(_), do: nil

  defp parse_numbering(nil), do: %__MODULE__{}.numbering

  defp parse_numbering(%{} = numbering) do
    n = stringify(numbering)

    %{
      enabled: n["enabled"] == true,
      region: if(n["region"] in [:header, "header"], do: :header, else: :footer),
      align: parse_align(n["align"]),
      format:
        case n["format"] do
          value when is_binary(value) and value != "" ->
            String.slice(value, 0, @max_slot_length)

          _ ->
            "{page}"
        end
    }
  end

  defp parse_numbering(_), do: %__MODULE__{}.numbering

  defp parse_align(align) when align in [:left, "left"], do: :left
  defp parse_align(align) when align in [:right, "right"], do: :right
  defp parse_align(_), do: :center

  defp parse_title(title) when is_binary(title) and title != "",
    do: String.slice(title, 0, @max_slot_length)

  defp parse_title(_), do: nil

  # Numbers are millimetres; strings may carry a CSS unit.
  defp length_mm(value) when is_number(value), do: value * 1.0

  defp length_mm(value) when is_binary(value) do
    case Regex.run(~r/^\s*(-?\d+(?:\.\d+)?)\s*(mm|cm|in|pt|px)?\s*$/i, value) do
      [_, number] -> to_float(number)
      [_, number, unit] -> to_float(number) * unit_factor(String.downcase(unit))
      _ -> nil
    end
  end

  defp length_mm(_), do: nil

  defp unit_factor("cm"), do: 10.0
  defp unit_factor("in"), do: 25.4
  defp unit_factor("pt"), do: 25.4 / 72
  defp unit_factor("px"), do: 25.4 / 96
  defp unit_factor(_), do: 1.0

  defp to_float(number) do
    {value, _rest} = Float.parse(number)
    value
  end

  # -------------------------------------------------------------------
  # Helpers
  # -------------------------------------------------------------------

  defp base_size(%{width: w, height: h}), do: {w, h}
  defp base_size(preset), do: Map.get(@presets, preset, @presets.letter)

  defp size_to_json(%{width: w, height: h}), do: %{"width" => w, "height" => h}
  defp size_to_json(preset), do: Atom.to_string(preset)

  # A slot with no image serialises back to the bare string it came from, so
  # documents without logos keep the JSON shape they already had.
  defp region_to_json(region),
    do: Map.new(region, fn {slot, value} -> {Atom.to_string(slot), slot_to_json(value)} end)

  defp slot_to_json(%{text: text, image: nil}), do: text

  defp slot_to_json(%{text: text, image: image}) do
    %{
      "text" => text,
      "image" => %{"src" => image.src, "alt" => image.alt, "height" => image.height}
    }
  end

  defp mm(value), do: "#{value |> Float.round(4) |> trim_float()}mm"

  # 25.4 -> "25.4", 210.0 -> "210"
  defp trim_float(value) do
    if value == Float.round(value),
      do: value |> trunc() |> Integer.to_string(),
      else: Float.to_string(value)
  end

  defp doc_page(doc) when is_map(doc) do
    case fetch_field(doc, "attrs") do
      %{} = attrs -> attrs |> stringify() |> Map.get("page")
      _ -> nil
    end
  end

  defp doc_page(_), do: nil

  # Documents reach us with string keys (JSON from the client) or atom keys
  # (hand-written in tests/seeds); support both without normalising the whole
  # — potentially large — document.
  defp fetch_field(map, key) when is_map(map) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, String.to_existing_atom(key))
    end
  rescue
    ArgumentError -> nil
  end

  defp put_field(map, key, value) do
    atom = safe_atom(key)

    if is_atom(atom) and Map.has_key?(map, atom),
      do: Map.put(map, atom, value),
      else: Map.put(map, key, value)
  end

  defp drop_field(map, key), do: map |> Map.delete(key) |> Map.delete(safe_atom(key))

  defp safe_atom(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> key
  end

  defp stringify_or_empty(%{} = map), do: stringify(map)
  defp stringify_or_empty(_), do: %{}

  defp stringify(%{} = map) do
    Map.new(map, fn {k, v} -> {key_to_string(k), stringify(v)} end)
  end

  defp stringify(list) when is_list(list), do: Enum.map(list, &stringify/1)
  defp stringify(other), do: other

  defp key_to_string(key) when is_atom(key), do: Atom.to_string(key)
  defp key_to_string(key), do: to_string(key)

  defp deep_merge(%{} = base, %{} = override) do
    Map.merge(base, override, fn
      _key, %{} = a, %{} = b -> deep_merge(a, b)
      _key, _a, b -> b
    end)
  end
end
