PYTHON ?= python3

.PHONY: extract build check test smoke inventory

extract:
	$(PYTHON) tools/reconstruct.py extract
	$(PYTHON) tools/extract_assets.py

build:
	$(PYTHON) tools/reconstruct.py build

check: build
	$(PYTHON) tools/reconstruct.py check

test:
	$(PYTHON) -m unittest discover -s tools -p 'test_*.py'

smoke:
	$(PYTHON) tools/reconstruct.py smoke

inventory:
	$(PYTHON) tools/reconstruct.py inventory
