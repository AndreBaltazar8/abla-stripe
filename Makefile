ABLAC_DIR := $(abspath ../ablac)
COMPILER ?= $(ABLAC_DIR)/build/ablac

.PHONY: check test clean

check:
	mkdir -p build
	bash -n tools/test-stripe.sh
	python3 -m py_compile tools/stripe_mock.py
	$(COMPILER) build tests/compile_test.ab -o build/compile-test --fast --no-cache
	$(COMPILER) build tests/form_test.ab -o build/form-test --fast --no-cache
	$(COMPILER) build tests/webhook_test.ab -o build/webhook-test --fast --no-cache
	$(COMPILER) build tests/service_test.ab -o build/service-test --fast --no-cache
	$(COMPILER) build tests/typed_services_test.ab -o build/typed-services-test --fast --no-cache
	$(COMPILER) build tests/pagination_test.ab -o build/pagination-test --fast --no-cache
	$(COMPILER) build tests/client_test.ab -o build/client-test --fast --no-cache
	$(COMPILER) build tests/safety_test.ab -o build/safety-test --fast --no-cache
	$(COMPILER) build tests/resources_test.ab -o build/resources-test --fast --no-cache
	$(COMPILER) build tests/config_test.ab -o build/config-test --fast --no-cache
	$(COMPILER) build tests/integration_test.ab -o build/integration-test --fast --no-cache
	build/form-test
	build/webhook-test
	build/service-test
	build/typed-services-test
	build/pagination-test
	build/client-test
	build/safety-test
	build/resources-test
	STRIPE_SECRET_KEY_FILE="$(CURDIR)/tests/secret_key_fixture.txt" \
		STRIPE_CONFIG_EXPECTED_KEY="sk_test_secret_from_file" \
		STRIPE_TIMEOUT_MS=4242 STRIPE_MAX_NETWORK_RETRIES=3 \
		STRIPE_ENABLE_TELEMETRY=true build/config-test
	STRIPE_SECRET_KEY="sk_test_direct_precedence" \
		STRIPE_SECRET_KEY_FILE="/does/not/exist" \
		STRIPE_CONFIG_EXPECTED_KEY="sk_test_direct_precedence" \
		STRIPE_TIMEOUT_MS=4242 STRIPE_MAX_NETWORK_RETRIES=3 \
		STRIPE_ENABLE_TELEMETRY=true build/config-test

test: check
	./tools/test-stripe.sh

clean:
	rm -rf build
