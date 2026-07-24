defmodule Tiptapex.PageTest do
  use ExUnit.Case, async: true

  alias Tiptapex.Page

  doctest Tiptapex.Page

  describe "new/1" do
    test "defaults to US Letter, portrait, one-inch margins" do
      page = Page.new()

      assert page.size == :letter
      assert page.orientation == :portrait
      assert page.margins == %{top: 25.4, right: 25.4, bottom: 25.4, left: 25.4}

      assert page.header == %{
               left: %{text: "", image: nil},
               center: %{text: "", image: nil},
               right: %{text: "", image: nil}
             }

      assert page.numbering.enabled == false
    end

    test "accepts string keys, atom keys and keyword lists alike" do
      from_strings = Page.new(%{"size" => "legal", "orientation" => "landscape"})
      from_atoms = Page.new(%{size: :legal, orientation: :landscape})
      from_keywords = Page.new(size: :legal, orientation: :landscape)

      assert from_strings == from_atoms
      assert from_atoms == from_keywords
    end

    test "reads CSS units in lengths, and bare numbers as millimetres" do
      page =
        Page.new(%{
          margins: %{top: "1in", right: "2cm", bottom: "36pt", left: 12.7}
        })

      assert page.margins.top == 25.4
      assert page.margins.right == 20.0
      assert_in_delta page.margins.bottom, 12.7, 0.0001
      assert page.margins.left == 12.7
    end

    test "keeps custom paper sizes" do
      page = Page.new(%{size: %{width: 200, height: 250}})
      assert Page.dimensions(page) == %{width: 200.0, height: 250.0}
    end

    test "falls back rather than raising on junk — the input is stored data" do
      page =
        Page.new(%{
          size: "papyrus",
          orientation: "sideways",
          margins: %{top: "wat"},
          header: %{left: 42},
          numbering: %{enabled: "yes", align: "middle", format: ""}
        })

      assert page.size == :letter
      assert page.orientation == :portrait
      assert page.margins.top == 25.4
      assert page.header.left == %{text: "", image: nil}
      assert page.numbering.enabled == false
      assert page.numbering.align == :center
      assert page.numbering.format == "{page}"
    end

    test "bounds header/footer text (it becomes a shell argument downstream)" do
      page = Page.new(%{footer: %{center: String.duplicate("a", 900)}})
      assert String.length(page.footer.center.text) == 500
    end

    test "new/1 is idempotent over a struct" do
      page = Page.new(%{size: :a4})
      assert Page.new(page) == page
    end
  end

  describe "dimensions/1 and content_box/1" do
    test "landscape swaps the axes" do
      assert Page.dimensions(Page.new(%{size: :letter, orientation: :landscape})) ==
               %{width: 279.4, height: 215.9}
    end

    test "the content box is the paper minus the margins" do
      page = Page.new(%{size: :a4, margins: %{top: 20, right: 15, bottom: 20, left: 15}})
      assert Page.content_box(page) == %{width: 180.0, height: 257.0}
    end

    test "margins larger than the paper clamp at zero instead of going negative" do
      page = Page.new(%{size: :a5, margins: %{top: 200, bottom: 200, left: 200, right: 200}})
      assert Page.content_box(page) == %{width: 0.0, height: 0.0}
    end
  end

  describe "from_doc/2" do
    setup do
      doc = %{
        "type" => "doc",
        "attrs" => %{"page" => %{"size" => "legal", "margins" => %{"top" => 10}}},
        "content" => []
      }

      %{doc: doc}
    end

    test "returns nil for a document with no page setup" do
      assert Page.from_doc(%{"type" => "doc", "content" => []}) == nil
      assert Page.from_doc(nil) == nil
    end

    test "reads the document's own setup", %{doc: doc} do
      page = Page.from_doc(doc)
      assert page.size == :legal
      assert page.margins.top == 10.0
      assert page.margins.bottom == 25.4
    end

    test "false wins over the document", %{doc: doc} do
      assert Page.from_doc(doc, false) == nil
    end

    test "true forces defaults onto an unpaginated document" do
      assert Page.from_doc(%{"type" => "doc"}, true) == Page.new()
    end

    test "a map is deep-merged over the document's setup", %{doc: doc} do
      page = Page.from_doc(doc, %{orientation: :landscape, margins: %{bottom: 5}})

      assert page.size == :legal, "untouched keys survive the merge"
      assert page.orientation == :landscape
      assert page.margins.top == 10.0
      assert page.margins.bottom == 5.0
    end

    test "a struct is taken as-is", %{doc: doc} do
      page = Page.new(%{size: :a4})
      assert Page.from_doc(doc, page) == page
    end

    test "reads atom-keyed documents too" do
      doc = %{type: "doc", attrs: %{page: %{size: :a4}}, content: []}
      assert Page.from_doc(doc).size == :a4
    end
  end

  describe "put/2" do
    test "stores the setup on the doc node and round-trips through from_doc" do
      doc = Page.put(%{"type" => "doc", "content" => []}, %{size: :legal})

      assert %{"attrs" => %{"page" => %{"size" => "legal"}}} = doc
      assert Page.from_doc(doc).size == :legal
      assert doc["content"] == []
    end

    test "nil removes it, leaving no empty attrs behind" do
      doc = Page.put(%{"type" => "doc", "content" => []}, %{size: :legal})
      assert Page.put(doc, nil) == %{"type" => "doc", "content" => []}
      assert Page.from_doc(Page.put(doc, nil)) == nil
    end

    test "keeps other doc attributes" do
      doc =
        %{"type" => "doc", "attrs" => %{"other" => 1}, "content" => []}
        |> Page.put(%{size: :a4})

      assert doc["attrs"]["other"] == 1
      assert doc["attrs"]["page"]["size"] == "a4"
    end
  end

  describe "slots/2 and region_used?/2" do
    test "an unused region has three empty slots" do
      page = Page.new()

      assert Page.slots(page, :footer) == [
               {:left, %{text: "", image: nil}},
               {:center, %{text: "", image: nil}},
               {:right, %{text: "", image: nil}}
             ]

      refute Page.region_used?(page, :footer)
    end

    test "numbering lands in the configured region and slot" do
      page =
        Page.new(%{
          numbering: %{enabled: true, region: :footer, align: :right, format: "— {page} —"}
        })

      assert Page.slots(page, :footer) == [
               {:left, %{text: "", image: nil}},
               {:center, %{text: "", image: nil}},
               {:right, %{text: "— {page} —", image: nil}}
             ]

      assert Page.region_used?(page, :footer)
      refute Page.region_used?(page, :header)
    end

    test "numbering appends to an occupied slot" do
      page =
        Page.new(%{
          footer: %{center: "Confidential"},
          numbering: %{enabled: true, align: :center, format: "{page}"}
        })

      assert {:center, %{text: "Confidential {page}"}} =
               List.keyfind(Page.slots(page, :footer), :center, 0)
    end

    test "a slot that already places {page} itself is left alone" do
      page =
        Page.new(%{
          footer: %{center: "{page} / {pages}"},
          numbering: %{enabled: true, align: :center, format: "{page}"}
        })

      assert {:center, %{text: "{page} / {pages}"}} =
               List.keyfind(Page.slots(page, :footer), :center, 0)
    end
  end

  describe "header/footer images" do
    test "a slot accepts an image alongside its text" do
      page =
        Page.new(%{header: %{left: %{text: "Acme", image: %{src: "/logo.png", height: 12}}}})

      assert page.header.left.text == "Acme"
      assert page.header.left.image == %{src: "/logo.png", alt: "", height: 12.0}
      assert Page.region_used?(page, :header)
      assert Page.images?(page)
    end

    test "an image alone makes the region used" do
      page = Page.new(%{footer: %{right: %{image: %{src: "/logo.png"}}}})

      assert Page.region_used?(page, :footer)
      refute Page.region_used?(page, :header)
      refute Page.images?(Page.new())
    end

    test "height defaults, reads CSS units and is clamped" do
      image = fn attrs -> Page.new(%{header: %{left: %{image: attrs}}}).header.left.image end

      assert image.(%{src: "/l.png"}).height == 8.0
      assert image.(%{src: "/l.png", height: "0.5in"}).height == 12.7
      assert image.(%{src: "/l.png", height: 5000}).height == 100.0
      assert image.(%{src: "/l.png", height: 0}).height == 8.0
    end

    test "image data URIs are allowed — they are how a logo reaches Chrome" do
      src = "data:image/png;base64,iVBORw0KGgo="
      page = Page.new(%{header: %{left: %{image: %{src: src}}}})

      assert page.header.left.image.src == src
    end

    test "a src the renderer would reject drops the image entirely" do
      for src <- [
            "javascript:alert(1)",
            "data:text/html;base64,PHNjcmlwdD4=",
            "data:image/png",
            "",
            nil,
            42
          ] do
        page = Page.new(%{header: %{left: %{text: "kept", image: %{src: src}}}})

        assert page.header.left.image == nil, "expected #{inspect(src)} to be rejected"
        assert page.header.left.text == "kept"
      end
    end

    test "numbering merges into the text of a slot that also has an image" do
      page =
        Page.new(%{
          footer: %{center: %{text: "", image: %{src: "/l.png"}}},
          numbering: %{enabled: true, align: :center, format: "{page}"}
        })

      assert {:center, %{text: "{page}", image: %{src: "/l.png"}}} =
               List.keyfind(Page.slots(page, :footer), :center, 0)
    end

    test "to_map/1 keeps the compact string form until a slot has an image" do
      page =
        Page.new(%{
          header: %{left: "plain", right: %{text: "with", image: %{src: "/l.png", height: 12}}}
        })

      map = Page.to_map(page)

      assert map["header"]["left"] == "plain"
      assert map["header"]["center"] == ""

      assert map["header"]["right"] == %{
               "text" => "with",
               "image" => %{"src" => "/l.png", "alt" => "", "height" => 12.0}
             }

      assert Page.new(Jason.decode!(Jason.encode!(map))) == page
    end
  end

  describe "replace_tokens/2" do
    test "replaces known tokens and blanks unlisted ones" do
      assert Page.replace_tokens("{title} — {page}/{pages} · {date}", %{
               "title" => "Report",
               "page" => "1",
               "pages" => "9"
             }) == "Report — 1/9 · "
    end

    test "leaves unknown braces alone" do
      assert Page.replace_tokens("{nope} {page}", %{"page" => "1"}) == "{nope} 1"
    end
  end

  describe "css helpers" do
    test "css_size/1 and css_margin/1 emit millimetres without trailing zeros" do
      page = Page.new(%{size: :a4, margins: %{top: 20, right: 15, bottom: 20, left: 15}})

      assert Page.css_size(page) == "210mm 297mm"
      assert Page.css_margin(page) == "20mm 15mm 20mm 15mm"
      assert Page.css_size(Page.new(%{size: :letter})) == "215.9mm 279.4mm"
    end
  end

  describe "to_map/1" do
    test "produces the JSON shape the client and the doc attribute carry" do
      map = Page.to_map(Page.new(%{size: :legal, footer: %{center: "{page}"}}))

      assert map["size"] == "legal"
      assert map["orientation"] == "portrait"
      assert map["margins"]["top"] == 25.4
      assert map["footer"] == %{"left" => "", "center" => "{page}", "right" => ""}
      assert map["header"] == %{"left" => "", "center" => "", "right" => ""}
      assert map["numbering"]["region"] == "footer"
      assert {:ok, _json} = Jason.encode(map)
    end

    test "round-trips through JSON without drift" do
      page = Page.new(%{size: %{width: 200, height: 250}, orientation: :landscape, title: "T"})
      encoded = page |> Page.to_map() |> Jason.encode!() |> Jason.decode!()

      assert Page.new(encoded) == page
    end
  end
end
