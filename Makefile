.PHONY: help setup run test clean contracts deploy-contract

help:
	@echo "BCH Oracle - Available commands:"
	@echo ""
	@echo "  make setup           - Install all dependencies"
	@echo "  make run             - Start the oracle service"
	@echo "  make test            - Run integration tests"
	@echo "  make contracts       - Set up BCH contracts"
	@echo "  make deploy-contract - Deploy contract for a task (TASK_ID=1)"
	@echo "  make clean           - Clean build artifacts"
	@echo ""

setup:
	@echo "Installing Gleam dependencies..."
	gleam deps download
	@echo "Setting up contracts..."
	cd contracts && ./setup.sh
	@echo ""
	@echo "✓ Setup complete!"
	@echo ""
	@echo "Next steps:"
	@echo "  1. Copy .env.example to .env"
	@echo "  2. Add your LLM_API_KEY to .env"
	@echo "  3. (Optional) Add BCH_ORACLE_WIF for on-chain publishing"
	@echo "  4. Run: make run"

run:
	@if [ ! -f .env ]; then \
		echo "Error: .env file not found. Copy .env.example to .env first."; \
		exit 1; \
	fi
	@echo "Starting BCH Oracle service..."
	@export $$(cat .env | xargs) && gleam run

test:
	@./test-integration.sh

contracts:
	@cd contracts && ./setup.sh

deploy-contract:
	@if [ -z "$(TASK_ID)" ]; then \
		echo "Error: TASK_ID not specified. Usage: make deploy-contract TASK_ID=1"; \
		exit 1; \
	fi
	@cd contracts && node deploy.js $(TASK_ID)

clean:
	@echo "Cleaning build artifacts..."
	@rm -rf build/
	@rm -f oracle.db
	@rm -rf contracts/node_modules
	@rm -rf contracts/artifacts
	@echo "✓ Clean complete"
