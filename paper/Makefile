# Build the LaTeX paper. Requires a full TeX Live with pdflatex, bibtex, and
# the `charter`, `natbib`, `booktabs`, `titlesec`, `orcidlink`, `hyperref`,
# `listings`, `enumitem`, `microtype`, `fancyhdr`, `setspace`, `helvet`,
# `tabularx` packages.

MAIN = paper
OUT  = $(MAIN).pdf

.PHONY: all clean distclean view

all: $(OUT)

$(OUT): $(MAIN).tex references.bib
	pdflatex -interaction=nonstopmode $(MAIN).tex
	-bibtex $(MAIN)
	pdflatex -interaction=nonstopmode $(MAIN).tex
	pdflatex -interaction=nonstopmode $(MAIN).tex

view: $(OUT)
	xdg-open $(OUT) >/dev/null 2>&1 &

clean:
	rm -f $(MAIN).aux $(MAIN).bbl $(MAIN).blg $(MAIN).log $(MAIN).out \
	      $(MAIN).toc $(MAIN).lof $(MAIN).lot $(MAIN).fls $(MAIN).fdb_latexmk

distclean: clean
	rm -f $(OUT)
