// Offline tests for the minimal XML reader used for ANN (Task 4).
// Run: cd supabase/functions/_shared && deno test --no-prompt catalogue/
import { strict as assert } from "node:assert";
import { childrenNamed, firstChild, parseXml, XmlParseError } from "./xml.ts";

Deno.test("parsesElementsAttributesAndText", () => {
  const root = parseXml(`<?xml version="1.0" encoding="utf-8"?>
<ann><anime id="4658" name='Jinki:Extend'><info type="Genres">drama</info><info type="Genres">science fiction</info><empty/></anime></ann>`);
  assert.equal(root.name, "ann");
  const anime = firstChild(root, "anime");
  assert.ok(anime);
  assert.equal(anime.attrs.id, "4658");
  assert.equal(anime.attrs.name, "Jinki:Extend");
  assert.deepEqual(childrenNamed(anime, "info").map((n) => n.text), ["drama", "science fiction"]);
  assert.equal(firstChild(anime, "empty")?.children.length, 0);
});

Deno.test("decodesEntitiesCdataAndKeepsMarkupLikeTextInert", () => {
  const root = parseXml(`<a x="1 &amp; 2"><t>&quot;FLY&quot; &lt;i&gt;Mirai&lt;/i&gt; &#233;&#x1F600;</t><c><![CDATA[<not a tag> & raw]]></c><!-- gone --></a>`);
  assert.equal(root.attrs.x, "1 & 2");
  assert.equal(firstChild(root, "t")?.text, `"FLY" <i>Mirai</i> é😀`);
  assert.equal(firstChild(root, "c")?.text, "<not a tag> & raw");
  assert.equal(root.children.length, 2, "decoded text never becomes elements");
});

Deno.test("mixedContentKeepsDirectTextAndChildElements", () => {
  const root = parseXml(`<info type="Picture">caption<img src="a.jpg"/></info>`);
  assert.equal(root.text, "caption");
  assert.equal(firstChild(root, "img")?.attrs.src, "a.jpg");
});

Deno.test("malformedInputThrows", () => {
  for (const bad of ["<a><b></a>", "<a>", "", "plain", "<a attr=1></a>", "<a></a><b></b>"]) {
    assert.throws(() => parseXml(bad), XmlParseError, bad);
  }
});

Deno.test("deepNestingIsRejected", () => {
  const deep = "<a>".repeat(500) + "</a>".repeat(500);
  assert.throws(() => parseXml(deep), XmlParseError);
});
