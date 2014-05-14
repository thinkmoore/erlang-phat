paper = paper
TEX = pdflatex
BIBTEX = bibtex

$(paper) : $(paper).tex *.tex 
	$(TEX) $(paper) &&\
	$(BIBTEX) $(paper)
	$(TEX) $(paper)
	$(TEX) $(paper)


clean: 
	rm paper.pdf *.aux  *.bbl *.blg *.log .Z*paper*

appendix:
	pdflatex appendix.tex
	pdflatex appendix.tex

latexmk:
	latexmk -cd -quiet -f -pdf -pdflatex='pdflatex -interaction=batchmode' -synctex=1 $(paper).tex
pvc:
	latexmk -cd -quiet -f -pdf -pdflatex='pdflatex -interaction=batchmode' -synctex=1 $(paper).tex -pvc


