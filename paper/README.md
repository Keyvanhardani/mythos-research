# LaTeX source

`paper.tex` is the arXiv-ready LaTeX source of the research report. It
covers the same material as `../RESEARCH.md` and is styled to mirror the
WeasyPrint-built PDF at `../dist/Mythos-Research-Edition.pdf`.

## Build

```bash
make         # pdflatex + bibtex + pdflatex + pdflatex
make clean   # remove build artefacts but keep the PDF
```

Dependencies (TeX Live): `charter`, `natbib`, `booktabs`, `titlesec`,
`orcidlink`, `hyperref`, `listings`, `enumitem`, `microtype`, `fancyhdr`,
`setspace`, `helvet`, `tabularx`.

On Debian/Ubuntu:

```bash
sudo apt install texlive-latex-recommended texlive-fonts-recommended \
                 texlive-latex-extra texlive-bibtex-extra texlive-science
```

## arXiv submission

The source here is intended to be uploadable as the arXiv tarball:

```bash
tar czf mythos-research.tar.gz paper.tex references.bib
```

arXiv will compile it with its own TeX Live; no pre-built PDF is required.
Category: `cs.CR` (Computer Science -- Cryptography and Security), with
secondary `cs.LG` (Machine Learning) optional.
