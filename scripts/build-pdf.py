#!/usr/bin/env python3
"""
Build a TU-Darmstadt-styled research report PDF from RESEARCH.md.

Conventions applied (TU Darmstadt Vorschlag zur formalen Gestaltung, VWL 2):
- Body: Bitstream Charter 11pt, 1.5 line spacing, justified, 6pt after paragraph.
- Headings: DejaVu Sans (FrontPage substitute) 14/12/11pt bold, thin rules
  top & bottom, numbered via Markdown source.
- Margins: 3 cm top, 3 cm left, 2.5 cm bottom, 2 cm right (A4).
- Footer: page number right-aligned.
- Structure: Cover - Abstract - Table of Contents - Body - References.
- References compiled from the URLs found inline in RESEARCH.md, rendered in
  an APA-adjacent style (alphabetical).
- Bold usage is intentionally softened (weight 600) to avoid the
  "everything is important" look that full-weight bold produces when
  Markdown sources use `**term**:` at the start of every bullet.

Output: dist/Mythos-Research-Edition.pdf
"""

from __future__ import annotations

import html
import pathlib
import re
import sys

import markdown
from weasyprint import HTML, CSS

ROOT = pathlib.Path(__file__).resolve().parents[1]
SRC = ROOT / "RESEARCH.md"
OUT_DIR = ROOT / "dist"
OUT_DIR.mkdir(exist_ok=True)
OUT = OUT_DIR / "Mythos-Research-Edition.pdf"

TITLE = "An Outside-In Replication of Project Glasswing"
SUBTITLE = (
    "Mythos Research Edition &ndash; a sink-guided, agentic pipeline "
    "for defensive vulnerability discovery with a general-purpose frontier model"
)
AUTHOR = "Keyvan Hardani"
AFFIL = "Independent Applied AI Research"
CONTACT = "hello@keyvan.ai"
ORCID = "0009-0000-6003-8826"
DOI_CONCEPT = "10.5281/zenodo.19727857"
DOI_VERSION = "10.5281/zenodo.19727858"
LINKS = "keyvan.ai &middot; github.com/Keyvanhardani &middot; linkedin.com/in/keyvanhardani"
DATE = "April 2026"
VERSION = "Research Report, version 1.0 (Research Edition v3.1-preview)"

ABSTRACT = (
    "Anthropic's April 2026 Mythos Preview (Project Glasswing) reports substantial "
    "gains in autonomous vulnerability discovery from a specialised model checkpoint "
    "paired with a comparatively simple agentic scaffold. This report examines the "
    "<em>scaffold</em> contribution in isolation and documents an outside-in "
    "replication built around a general-purpose frontier model "
    "(Claude&nbsp;Opus&nbsp;4.7). A seven-phase, sink-guided pipeline&mdash;language "
    "detection, sink slicing, file ranking, agentic hunting, skeptical validation, "
    "live-execution (held out of the public repository), and aggregation&mdash;is "
    "described together with the vulnerability-semantics prompts that drive it. "
    "The report separates what structured prompting and scaffolding can plausibly "
    "close from what remains weight-level capability, draws on the public literature "
    "on agentic security agents, and gives an indicative per-run cost profile for "
    "the targeted-scan configuration. No benchmark comparison against Project Glasswing "
    "itself is claimed; all quantitative statements about Glasswing performance are "
    "reproduced from the primary sources cited inline."
)

KEYWORDS = (
    "large language models; vulnerability discovery; agentic scaffolding; "
    "prompt engineering; sink analysis; coordinated disclosure; Claude; Glasswing"
)

# -- References ---------------------------------------------------------------
# Hand-compiled bibliography. Ordered alphabetically by first author/organisation.
# Where authors are not available from the source page, the hosting organisation
# is used instead, following the "corporate author" convention in APA.

REFERENCES = [
    ("Anthropic (2026a)", "<em>Claude Mythos Preview.</em> red.anthropic.com/2026/mythos-preview"),
    ("Anthropic (2026b)", "<em>Project Glasswing.</em> anthropic.com/project/glasswing"),
    ("Anthropic (2026c)", "<em>Introducing Claude Opus 4.7.</em> anthropic.com/news/claude-opus-4-7"),
    ("arXiv:2402.17230", "Vulnerability-Semantics-guided Prompting for pre-trained language models. arxiv.org/abs/2402.17230"),
    ("arXiv:2406.01637", "Teams of LLM Agents can Exploit Zero-Day Vulnerabilities (HPTSA). arxiv.org/abs/2406.01637"),
    ("arXiv:2503.17885", "VulnSage: Think &amp; Verify reasoning for LLM-based vulnerability detection. arxiv.org/abs/2503.17885"),
    ("arXiv:2509.07225", "All You Need Is A Fuzzing Brain: LLM-assisted fuzzing study. arxiv.org/html/2509.07225v1"),
    ("arXiv:2511.11250", "Prompt Engineering vs. Fine-Tuning for Vulnerability Detection. arxiv.org/html/2511.11250"),
    ("arXiv:2604.04561", "A 10,000-Trial Taxonomy of LLM Exploitation Behaviours. arxiv.org/abs/2604.04561"),
    ("BU SecLab (2025)", "<em>CVE-Genie: Multi-agent CVE reproduction.</em> github.com/BUseclab/cve-genie"),
    ("GitHub Security Lab (2025)", "<em>seclab-taskflow-agent: YAML-driven LLM security audit.</em> github.com/GitHubSecurityLab/seclab-taskflow-agent"),
    ("Huhusmang (2025)", "<em>Awesome-LLMs-for-Vulnerability-Detection.</em> github.com/huhusmang/Awesome-LLMs-for-Vulnerability-Detection"),
    ("Joern (2025)", "<em>Joern &ndash; code property graph platform.</em> joern.io"),
    ("Lekssays, A. et al. (2025)", "LLMxCPG: Code-Property-Graph-guided LLM queries for vulnerability detection. USENIX Security 2025. usenix.org/conference/usenixsecurity25/presentation/lekssays"),
    ("Liu, J. et al. (2025)", "Reasoning models for vulnerability detection: an analysis of DeepSeek-R1. <em>Applied Sciences</em>, 15(12), 6651. mdpi.com/2076-3417/15/12/6651"),
    ("Meta (2024)", "<em>PurpleLlama &amp; CyberSecEval.</em> github.com/meta-llama/PurpleLlama"),
    ("MindStudio (2026)", "<em>Claude Mythos vs. Opus&nbsp;4.6: the cybersecurity gap.</em> mindstudio.ai/blog/claude-mythos-vs-opus-4-6-cybersecurity-gap"),
    ("NDSS (2025)", "From Large to Mammoth: scaling LLM-based vulnerability detection. Paper&nbsp;1491. ndss-symposium.org/wp-content/uploads/2025-1491-paper.pdf"),
    ("Nong, Y. et al. (2025)", "APPATCH: semantics-aware vulnerability patching. USENIX Security 2025. usenix.org/conference/usenixsecurity25/presentation/nong"),
    ("NVD (2026)", "<em>CVE-2026-4747.</em> nvd.nist.gov/vuln/detail/CVE-2026-4747"),
    ("Project Zero (2024a)", "<em>Project Naptime: evaluating offensive security capabilities of LLMs.</em> projectzero.google/2024/06/project-naptime.html"),
    ("Project Zero (2024b)", "<em>From Naptime to Big Sleep.</em> projectzero.google/2024/10/from-naptime-to-big-sleep.html"),
    ("ProtectAI (2024)", "<em>Vulnhuntr: agentic Python vulnerability discovery.</em> github.com/protectai/vulnhuntr"),
    ("Semgrep (2026)", "<em>Needles and haystacks: can open-source &amp; flagship models do what Mythos did?</em> semgrep.dev/blog/2026/needles-and-haystacks-can-open-source-flagship-models-do-what-mythos-did"),
    ("Semgrep (n.d.)", "<em>Semgrep &ndash; static analysis platform.</em> semgrep.dev"),
    ("SWE-Agent (2024)", "<em>SWE-agent: agentic software-engineering framework.</em> github.com/SWE-agent/SWE-agent"),
    ("Tmylla (2025)", "<em>Awesome-LLM4Cybersecurity.</em> github.com/tmylla/Awesome-LLM4Cybersecurity"),
    ("VulnCheck (2026)", "<em>Tracking CVEs attributed to Anthropic researchers and Project Glasswing.</em> vulncheck.com/blog/anthropic-glasswing-cves"),
]


# -- Markdown processing ------------------------------------------------------

def preprocess_markdown(text: str) -> str:
    # strip the original top matter; we render our own cover
    text = re.sub(
        r"^# [^\n]+\n\n(?:>[^\n]*\n)+\n---\n",
        "",
        text,
        count=1,
        flags=re.MULTILINE,
    )
    text = text.replace("assets/", str((ROOT / "assets").as_posix()) + "/")
    return text


def render_body(md_text: str) -> str:
    md = markdown.Markdown(
        extensions=[
            "extra",
            "toc",
            "tables",
            "fenced_code",
            "codehilite",
            "sane_lists",
        ],
        extension_configs={
            "codehilite": {"guess_lang": False, "noclasses": True},
            "toc": {"anchorlink": False, "permalink": False, "toc_depth": "2-3"},
        },
    )
    return md.convert(md_text)


# -- Stylesheet ---------------------------------------------------------------

CSS_STYLE = r"""
@page {
  size: A4;
  margin: 3cm 2cm 2.5cm 3cm; /* top, right, bottom, left */
  @top-left { content: string(running-title); font-family: 'Bitstream Charter', serif;
    font-size: 9pt; color: #333; }
  @bottom-right { content: counter(page); font-family: 'DejaVu Sans', sans-serif;
    font-size: 9.5pt; font-weight: 700; color: #222; }
}
@page :first {
  margin: 3.5cm 2cm 2.5cm 3cm;
  @top-left { content: ""; }
  @bottom-right { content: ""; }
}

html { font-family: 'Bitstream Charter', 'Charter', 'Nimbus Roman', serif;
  font-size: 11pt; color: #111; }
body { line-height: 1.5; hyphens: auto; text-align: justify;
  string-set: running-title "Outside-In Replication of Project Glasswing"; }

/* -- Cover (Deckblatt) ---------------------------------------------------- */
.cover { page-break-after: always; text-align: left; }
.cover .ident { border-top: 3px solid #111; padding-top: 8pt; margin-bottom: 40pt; }
.cover .ident .label { font-family: 'DejaVu Sans', sans-serif; font-size: 9pt;
  font-weight: 700; letter-spacing: 1.5pt; text-transform: uppercase; color: #111; }
.cover .ident .sub { font-family: 'DejaVu Sans', sans-serif; font-size: 9pt;
  color: #444; margin-top: 2pt; }
.cover h1 { font-family: 'DejaVu Sans', sans-serif; font-size: 22pt; line-height: 1.18;
  font-weight: 700; margin: 0 0 8pt 0; color: #111; letter-spacing: -0.2pt; }
.cover h2 { font-family: 'Bitstream Charter', serif; font-size: 12.5pt;
  font-weight: 400; font-style: italic; color: #333; margin: 0 0 28pt 0; line-height: 1.4; }
.cover .author-block { margin-top: 18pt; }
.cover .author-block .author { font-family: 'DejaVu Sans', sans-serif;
  font-size: 12pt; font-weight: 700; color: #111; }
.cover .author-block .affil { font-family: 'Bitstream Charter', serif;
  font-size: 10.5pt; color: #333; margin-top: 2pt; }
.cover .author-block .contact { font-family: 'Bitstream Charter', serif;
  font-size: 10pt; color: #444; margin-top: 2pt; }
.cover .meta-bottom { position: running(covermeta); border-top: 0.5pt solid #666;
  padding-top: 6pt; font-family: 'DejaVu Sans', sans-serif; font-size: 9pt; color: #444; }
.cover .footer-block { margin-top: 60pt; border-top: 0.5pt solid #666; padding-top: 8pt;
  font-family: 'DejaVu Sans', sans-serif; font-size: 9pt; color: #444; line-height: 1.5; }
.cover .footer-block .row { margin-top: 3pt; }
.cover .footer-block .k { display: inline-block; width: 100pt; color: #666;
  text-transform: uppercase; letter-spacing: 0.8pt; font-size: 8.5pt; }

/* -- Frontmatter (Abstract, ToC) ------------------------------------------ */
.frontmatter { page-break-after: always; }
.frontmatter h1.frontmatter-head { font-family: 'DejaVu Sans', sans-serif;
  font-size: 14pt; font-weight: 700; margin: 0 0 12pt 0;
  border-top: 0.5pt solid #111; border-bottom: 0.5pt solid #111;
  padding: 6pt 0; letter-spacing: 0.2pt; }
.frontmatter .abstract-body { text-align: justify; }
.frontmatter .abstract-body p { margin: 0 0 8pt 0; }
.frontmatter .keywords { margin-top: 10pt; font-size: 10pt; color: #222; }
.frontmatter .keywords .k { font-family: 'DejaVu Sans', sans-serif;
  font-weight: 700; font-size: 9pt; letter-spacing: 1pt; text-transform: uppercase; }

.toc { page-break-before: always; }
.toc h1.frontmatter-head { margin-bottom: 14pt; }
.toc ol { list-style: none; padding: 0; margin: 0; counter-reset: sec; }
.toc ol li { font-family: 'Bitstream Charter', serif; font-size: 11pt;
  margin: 2pt 0; display: flex; align-items: baseline; }
.toc ol li .num { width: 28pt; font-family: 'DejaVu Sans', sans-serif;
  font-weight: 700; font-size: 10pt; color: #222; }
.toc ol li .title { flex: 1; }
.toc ol li .dots { flex: 1; border-bottom: 1pt dotted #999; margin: 0 6pt;
  transform: translateY(-3pt); }

/* -- Body headings (numbered in Markdown source) -------------------------- */
h1, h2, h3, h4 { font-family: 'DejaVu Sans', sans-serif; color: #111;
  page-break-after: avoid; }
h1 { font-size: 14pt; font-weight: 700; margin: 18pt 0 8pt 0;
  border-top: 0.5pt solid #111; border-bottom: 0.5pt solid #111;
  padding: 5pt 0; line-height: 1.25; }
h2 { font-size: 12pt; font-weight: 700; margin: 14pt 0 6pt 0;
  border-bottom: 0.5pt solid #888; padding-bottom: 3pt; line-height: 1.3; }
h3 { font-size: 11pt; font-weight: 700; margin: 10pt 0 4pt 0; line-height: 1.3; }
h4 { font-size: 10.5pt; font-weight: 700; margin: 8pt 0 3pt 0; }

p { margin: 0 0 6pt 0; orphans: 3; widows: 3; }

/* Softer bold for inline <strong> so Markdown-style `**Term**:` lists
   don't shout throughout the document. */
strong, b { font-weight: 600; }

a { color: #111; text-decoration: none; border-bottom: 0.5pt solid #888; }

/* -- Tables --------------------------------------------------------------- */
table { width: 100%; border-collapse: collapse; margin: 8pt 0; font-size: 10pt;
  page-break-inside: avoid; font-family: 'Bitstream Charter', serif; }
table thead th { font-family: 'DejaVu Sans', sans-serif; font-size: 9.5pt;
  font-weight: 700; text-align: left; padding: 4pt 6pt;
  border-top: 0.75pt solid #111; border-bottom: 0.75pt solid #111;
  background: transparent; }
table tbody td { padding: 3pt 6pt; border-bottom: 0.25pt solid #bbb; vertical-align: top; }
table tbody tr:last-child td { border-bottom: 0.75pt solid #111; }

/* -- Code ----------------------------------------------------------------- */
pre, code { font-family: 'DejaVu Sans Mono', 'Nimbus Mono PS', monospace; }
code { font-size: 9.5pt; background: #f0f0f0; padding: 0 2pt; border-radius: 1pt; }
pre { font-size: 9pt; background: #f6f6f6; border-left: 2pt solid #555;
  padding: 6pt 8pt; margin: 6pt 0; white-space: pre-wrap; word-wrap: break-word;
  page-break-inside: avoid; line-height: 1.35; }
pre code { background: transparent; padding: 0; font-size: 9pt; }

/* -- Quotes --------------------------------------------------------------- */
blockquote { border-left: 2pt solid #555; padding: 2pt 10pt; margin: 6pt 0 6pt 1cm;
  color: #333; font-size: 10pt; line-height: 1.4; }

/* -- Figures -------------------------------------------------------------- */
img { max-width: 100%; display: block; margin: 8pt auto; }

/* -- Lists ---------------------------------------------------------------- */
ul, ol { margin: 4pt 0 6pt 18pt; padding: 0; }
li { margin: 2pt 0; }

hr { border: none; border-top: 0.5pt solid #aaa; margin: 12pt 0; }

/* -- References (Literaturverzeichnis) ------------------------------------ */
.references { page-break-before: always; }
.references h1 { margin-top: 0; }
.references ol { list-style: none; padding: 0; margin: 0; counter-reset: ref; }
.references ol li { font-family: 'Bitstream Charter', serif; font-size: 10pt;
  line-height: 1.4; padding-left: 28pt; text-indent: -28pt;
  margin: 0 0 5pt 0; text-align: left; hyphens: auto; }
.references ol li .key { font-family: 'DejaVu Sans', sans-serif;
  font-weight: 700; font-size: 9.5pt; color: #111; }

/* -- Closing page --------------------------------------------------------- */
.closing { page-break-before: always; }
.closing h1 { margin-top: 0; }
.closing .citation { font-family: 'DejaVu Sans Mono', monospace; font-size: 9pt;
  background: #f6f6f6; padding: 8pt 10pt; border-left: 2pt solid #555;
  white-space: pre-wrap; line-height: 1.4; margin: 6pt 0 12pt 0; }
.closing .note { font-size: 9.5pt; color: #444; line-height: 1.45; margin-top: 10pt; }
"""


# -- HTML composition ---------------------------------------------------------

def build_cover_html() -> str:
    return f"""
    <section class="cover">
      <div class="ident">
        <div class="label">Research Report &middot; {DATE}</div>
        <div class="sub">{VERSION}</div>
      </div>
      <h1>{TITLE}</h1>
      <h2>{SUBTITLE}</h2>

      <div class="author-block">
        <div class="author">{AUTHOR}</div>
        <div class="affil">{AFFIL}</div>
        <div class="contact">{CONTACT}</div>
        <div class="contact">ORCID: <a href="https://orcid.org/{ORCID}">{ORCID}</a></div>
        <div class="contact">DOI: <a href="https://doi.org/{DOI_CONCEPT}">{DOI_CONCEPT}</a></div>
      </div>

      <div class="footer-block">
        <div class="row"><span class="k">Issued</span> {DATE}</div>
        <div class="row"><span class="k">Status</span> Public research report, version 1.0</div>
        <div class="row"><span class="k">License</span> Apache&nbsp;License&nbsp;2.0 &middot; research and self-scan use</div>
        <div class="row"><span class="k">Repository</span> github.com/Keyvanhardani/mythos-research</div>
        <div class="row"><span class="k">ORCID</span> orcid.org/{ORCID}</div>
        <div class="row"><span class="k">DOI (concept)</span> doi.org/{DOI_CONCEPT}</div>
        <div class="row"><span class="k">DOI (v1.0.2)</span> doi.org/{DOI_VERSION}</div>
        <div class="row"><span class="k">Web</span> {LINKS}</div>
      </div>
    </section>
    """


def build_abstract_html() -> str:
    return f"""
    <section class="frontmatter">
      <h1 class="frontmatter-head">Abstract</h1>
      <div class="abstract-body"><p>{ABSTRACT}</p></div>
      <div class="keywords">
        <span class="k">Keywords &ndash;</span> {KEYWORDS}
      </div>

      <p class="keywords" style="margin-top:18pt;">
        <span class="k">Scope &amp; honesty statement &ndash;</span>
        This report is an <em>outside-in</em> replication of the scaffold described
        in Anthropic's publicly released Mythos Preview announcement. It does not
        attempt to reproduce the Mythos Preview checkpoint, and the live-exploit
        validation stage is deliberately held out of the public repository in line
        with coordinated-disclosure practice. All quantitative figures attributed
        to Project Glasswing are reproduced from the primary sources cited inline
        and are not independently measured here.
      </p>
    </section>
    """


def build_references_html() -> str:
    items = []
    for key, body in REFERENCES:
        items.append(
            f'<li><span class="key">{key}.</span> {body}</li>'
        )
    return f"""
    <section class="references">
      <h1>References</h1>
      <ol>
        {"".join(items)}
      </ol>
    </section>
    """


def build_closing_html() -> str:
    return f"""
    <section class="closing">
      <h1>How to cite &amp; availability</h1>
      <p>If you use Mythos Research Edition in academic or professional work,
      please cite the following report and the underlying repository:</p>
      <div class="citation">Hardani, K. (2026). An Outside-In Replication of Project Glasswing:
Mythos Research Edition &ndash; a sink-guided, agentic pipeline for
defensive vulnerability discovery with a general-purpose frontier model.
Independent research report, v1.0.2.
https://doi.org/{DOI_CONCEPT}</div>

      <p class="note">The scaffold, prompts, sink catalogues and orchestrator
      referenced throughout this report are published under the Apache&nbsp;License&nbsp;2.0
      at <em>github.com/Keyvanhardani/mythos-research</em>. The live-exploit-validation
      stage (Phase&nbsp;5), exploit-sketch generators and per-target tuning accumulated
      during real scans are kept outside the public repository in line with
      coordinated-disclosure practice.</p>

      <p class="note">No claim of having measured Project Glasswing performance
      independently is made; all Glasswing figures reproduced in this report are
      attributed to their primary sources. Cost figures for the Mythos Research
      Edition pipeline are indicative per-run estimates based on Anthropic API
      pricing at the time of writing (April&nbsp;2026) and targeted-scan
      configurations of roughly eight files per run.</p>

      <p class="note" style="color:#666; font-size:9pt; margin-top:18pt;">
        &copy; 2026 {AUTHOR}. Typeset with WeasyPrint from RESEARCH.md using a
        Charter&nbsp;/ DejaVu&nbsp;Sans combination approximating the TU&nbsp;Darmstadt
        Corporate-Design formatting guidelines for student theses.
      </p>
    </section>
    """


def build_html(body_html: str) -> str:
    return f"""<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><title>{TITLE}</title></head>
<body>
{build_cover_html()}
{build_abstract_html()}
{body_html}
{build_references_html()}
{build_closing_html()}
</body>
</html>"""


def main() -> int:
    if not SRC.exists():
        print(f"error: {SRC} not found", file=sys.stderr)
        return 1
    text = preprocess_markdown(SRC.read_text(encoding="utf-8"))
    body = render_body(text)
    # Wrap the Markdown-derived body in its own section so we can target it if needed.
    body_section = f'<section class="body">{body}</section>'
    html_doc = build_html(body_section)
    HTML(string=html_doc, base_url=str(ROOT)).write_pdf(
        target=str(OUT),
        stylesheets=[CSS(string=CSS_STYLE)],
    )
    size_kb = OUT.stat().st_size / 1024
    print(f"wrote {OUT}  ({size_kb:.0f} KB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
