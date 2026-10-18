PYTHON ?= python3

.PHONY: extract build check test smoke inventory korean-baseline korean-capacity korean-catalog korean-check korean-probe korean-draft-check korean-fixtures korean-draft-capacity korean-library korean-renderers korean-synthetic korean-review korean korean-image-check korean-synthetic-check korean-reproduce korean-release-check

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

korean-baseline:
	$(PYTHON) -m tools.korean.baseline

korean-capacity: build
	$(PYTHON) -m tools.korean.capacity

korean-catalog:
	$(PYTHON) -m tools.korean.catalog extract

korean-check:
	$(PYTHON) -m tools.korean.catalog check

korean-probe: korean-capacity
	$(PYTHON) -m tools.korean.probe

korean-draft-check:
	$(PYTHON) -m tools.korean.draft --complete

korean-fixtures:
	$(PYTHON) -m tools.korean.encoding

korean-draft-capacity:
	$(PYTHON) -m tools.korean.measure_draft

korean-library:
	$(PYTHON) -m tools.korean.library

korean-renderers:
	$(PYTHON) -m tools.korean.render_probe

korean-synthetic: korean-capacity
	$(PYTHON) -m tools.korean.synthetic

korean-review:
	$(PYTHON) -m tools.korean.review

korean:
	$(PYTHON) -m tools.korean.production

korean-image-check:
	$(PYTHON) -m tools.korean.image_check

korean-synthetic-check:
	$(PYTHON) -m tools.korean.image_check --synthetic

korean-reproduce:
	$(PYTHON) -m tools.korean.reproduce

korean-release-check:
	$(PYTHON) -m tools.korean.release_check
