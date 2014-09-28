
install-on-macosx:
	brew install phantomjs
	npm install temp phantom

install: install-on-macosx

.PHONY: install install-on-macosx
