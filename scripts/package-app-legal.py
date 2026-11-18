"""Build the clients' offline documents from the approved local Word files."""
import argparse
import json
import os
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path
from zipfile import ZipFile

WORD = "{http://schemas.openxmlformats.org/wordprocessingml/2006/main}"
REL_ID = "{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id"
STYLES = {"Title": "title", "Heading1": "heading", "Heading2": "subheading"}


def read_document(source):
    with ZipFile(source) as archive:
        body = ET.fromstring(archive.read("word/document.xml")).find(WORD + "body")
        relationships = ET.fromstring(archive.read("word/_rels/document.xml.rels"))
        links = {rel.get("Id"): rel.get("Target") for rel in relationships
                 if rel.get("Type", "").endswith("/hyperlink")}
    paragraphs = []
    for paragraph in body.findall(WORD + "p"):
        style = paragraph.find(f"{WORD}pPr/{WORD}pStyle")
        kind = STYLES.get(style.get(WORD + "val") if style is not None else "", "body")
        runs = []
        for element in paragraph:
            url = links[element.get(REL_ID)] if element.tag == WORD + "hyperlink" else None
            if url and not url.startswith(("https://", "mailto:")):
                raise ValueError("Unsupported legal-document link")
            for run in element.iter(WORD + "r"):
                parts = []
                for item in run:
                    if item.tag == WORD + "t":
                        parts.append(item.text or "")
                    elif item.tag == WORD + "tab":
                        parts.append("\t")
                    elif item.tag == WORD + "br" and item.get(WORD + "type") != "page":
                        parts.append("\n")
                if parts:
                    data = {"text": "".join(parts)}
                    bold = run.find(f"{WORD}rPr/{WORD}b")
                    if bold is not None and bold.get(WORD + "val") not in {"0", "false"}:
                        data["bold"] = True
                    if url:
                        data["url"] = url
                    runs.append(data)
        if runs:
            paragraphs.append({"kind": kind, "runs": runs})
    if not paragraphs or paragraphs[0]["kind"] != "title":
        raise ValueError("Missing document title")
    return paragraphs


def heading_index(paragraphs, title):
    return next(i for i, p in enumerate(paragraphs) if p["kind"] == "heading"
                and "".join(run["text"] for run in p["runs"]) == title)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("documents", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--version", required=True)
    args = parser.parse_args()
    privacy = read_document(args.documents / "我的川农隐私政策.docx")
    agreement = read_document(args.documents / "我的川农用户协议.docx")
    start = heading_index(privacy, "一　个人信息收集与使用清单")
    providers = heading_index(privacy, "三　第三方服务与 SDK 清单")
    end = heading_index(privacy, "四　委托、共享、公开及转移")
    documents = {"privacy": privacy, "agreement": agreement,
                 "collection": privacy[start:providers], "thirdparties": privacy[providers:end]}
    args.output.mkdir(mode=0o700, parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=args.output, mode="w", encoding="utf-8", delete=False) as out:
        json.dump({"version": args.version, "documents": documents}, out, ensure_ascii=False, separators=(",", ":"))
    os.replace(out.name, args.output / "MyChuannongLegal.json")


if __name__ == "__main__":
    main()
