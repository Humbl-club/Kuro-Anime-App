// Minimal, dependency-free XML reader for the ANN encyclopedia API (no network, no regex over
// markup). Handles elements, quoted attributes, self-closing tags, comments, processing
// instructions, DOCTYPE (skipped), CDATA and the five predefined entities plus numeric references.
// It does not resolve custom entities and never re-parses decoded text, so entity-encoded markup
// stays text. Nesting is capped so hostile input cannot exhaust the stack.
//
// Node.text is the concatenation of the node's direct text (trimmed); child elements are in
// `children`. One root element is required.

export type XmlNode = { name: string; attrs: Record<string, string>; children: XmlNode[]; text: string };

export class XmlParseError extends Error {
  constructor(message: string, public offset: number) {
    super(`${message} (at ${offset})`);
    this.name = "XmlParseError";
  }
}

const MAX_DEPTH = 100;
const NAMED: Record<string, string> = { amp: "&", lt: "<", gt: ">", quot: '"', apos: "'" };

function isSpace(c: string): boolean {
  return c === " " || c === "\n" || c === "\t" || c === "\r";
}

function isNameChar(c: string): boolean {
  return !isSpace(c) && c !== "/" && c !== ">" && c !== "=" && c !== "<" && c !== '"' && c !== "'";
}

export function decodeEntities(raw: string): string {
  if (!raw.includes("&")) return raw;
  let out = "";
  let i = 0;
  while (i < raw.length) {
    const amp = raw.indexOf("&", i);
    if (amp < 0) {
      out += raw.slice(i);
      break;
    }
    out += raw.slice(i, amp);
    const semi = raw.indexOf(";", amp);
    if (semi < 0 || semi - amp > 12) {
      out += "&";
      i = amp + 1;
      continue;
    }
    const body = raw.slice(amp + 1, semi);
    let decoded: string | null = null;
    if (body.startsWith("#x") || body.startsWith("#X")) {
      const cp = parseInt(body.slice(2), 16);
      if (Number.isInteger(cp) && cp > 0 && cp <= 0x10ffff) decoded = String.fromCodePoint(cp);
    } else if (body.startsWith("#")) {
      const cp = parseInt(body.slice(1), 10);
      if (Number.isInteger(cp) && cp > 0 && cp <= 0x10ffff) decoded = String.fromCodePoint(cp);
    } else if (body in NAMED) {
      decoded = NAMED[body];
    }
    if (decoded === null) {
      out += raw.slice(amp, semi + 1);
    } else {
      out += decoded;
    }
    i = semi + 1;
  }
  return out;
}

export function parseXml(input: string): XmlNode {
  let pos = 0;
  const n = input.length;
  const stack: { node: XmlNode; text: string[] }[] = [];
  let root: XmlNode | null = null;

  const fail = (message: string): never => {
    throw new XmlParseError(message, pos);
  };

  const addText = (raw: string, decode: boolean) => {
    const top = stack[stack.length - 1];
    if (top) top.text.push(decode ? decodeEntities(raw) : raw);
    else if (raw.trim()) fail("text outside the root element");
  };

  while (pos < n) {
    const lt = input.indexOf("<", pos);
    if (lt < 0) {
      addText(input.slice(pos), true);
      pos = n;
      break;
    }
    if (lt > pos) addText(input.slice(pos, lt), true);
    pos = lt;
    if (input.startsWith("<!--", pos)) {
      const end = input.indexOf("-->", pos + 4);
      if (end < 0) fail("unterminated comment");
      pos = end + 3;
    } else if (input.startsWith("<![CDATA[", pos)) {
      const end = input.indexOf("]]>", pos + 9);
      if (end < 0) fail("unterminated CDATA");
      addText(input.slice(pos + 9, end), false);
      pos = end + 3;
    } else if (input.startsWith("<?", pos)) {
      const end = input.indexOf("?>", pos + 2);
      if (end < 0) fail("unterminated processing instruction");
      pos = end + 2;
    } else if (input.startsWith("<!", pos)) {
      const end = input.indexOf(">", pos + 2);
      if (end < 0) fail("unterminated declaration");
      pos = end + 1;
    } else if (input.startsWith("</", pos)) {
      let p = pos + 2;
      const start = p;
      while (p < n && isNameChar(input[p])) p++;
      const name = input.slice(start, p);
      while (p < n && isSpace(input[p])) p++;
      if (input[p] !== ">") fail("malformed closing tag");
      const top = stack.pop();
      if (!top || top.node.name !== name) fail(`closing tag </${name}> does not match`);
      top!.node.text = top!.text.join("").trim();
      pos = p + 1;
    } else {
      let p = pos + 1;
      const start = p;
      while (p < n && isNameChar(input[p])) p++;
      const name = input.slice(start, p);
      if (!name) fail("empty tag name");
      const attrs: Record<string, string> = {};
      let selfClosing = false;
      while (true) {
        while (p < n && isSpace(input[p])) p++;
        if (p >= n) fail("unterminated tag");
        if (input[p] === ">") {
          p++;
          break;
        }
        if (input[p] === "/" && input[p + 1] === ">") {
          selfClosing = true;
          p += 2;
          break;
        }
        const aStart = p;
        while (p < n && isNameChar(input[p])) p++;
        const attr = input.slice(aStart, p);
        if (!attr) fail("malformed attribute");
        while (p < n && isSpace(input[p])) p++;
        if (input[p] !== "=") fail("attribute without value");
        p++;
        while (p < n && isSpace(input[p])) p++;
        const quote = input[p];
        if (quote !== '"' && quote !== "'") fail("attribute value must be quoted");
        const vEnd = input.indexOf(quote, p + 1);
        if (vEnd < 0) fail("unterminated attribute value");
        attrs[attr] = decodeEntities(input.slice(p + 1, vEnd));
        p = vEnd + 1;
      }
      pos = p;
      const node: XmlNode = { name, attrs, children: [], text: "" };
      const parent = stack[stack.length - 1];
      if (parent) parent.node.children.push(node);
      else if (root) fail("more than one root element");
      else root = node;
      if (!selfClosing) {
        if (stack.length >= MAX_DEPTH) fail("nesting too deep");
        stack.push({ node, text: [] });
      }
    }
  }
  if (stack.length > 0) fail("unclosed element");
  if (!root) fail("no root element");
  return root as XmlNode;
}

export function childrenNamed(node: XmlNode, name: string): XmlNode[] {
  return node.children.filter((c) => c.name === name);
}

export function firstChild(node: XmlNode, name: string): XmlNode | undefined {
  return node.children.find((c) => c.name === name);
}
