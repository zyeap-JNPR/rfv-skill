.PHONY: lint test

SCRIPT := skills/review-fix-verify/rfv-prep.sh

lint:
	bash -n $(SCRIPT)
	shellcheck -S warning $(SCRIPT)

test:
	bats tests/rfv-prep.bats
