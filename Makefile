BIN_DIR  := $(HOME)/.local/bin
CMD      := rboot
TARGET   := $(abspath bin/rboot)
LINK     := $(BIN_DIR)/$(CMD)

.PHONY: install uninstall

install:
	chmod +x $(TARGET)
	mkdir -p $(BIN_DIR)
	ln -sfn $(TARGET) $(LINK)
	@echo "Installed: $(LINK) -> $(TARGET)"
	@if [ ! -d $(HOME)/.rboot ]; then \
	  mkdir -p $(HOME)/.rboot; \
	  echo "Created: $(HOME)/.rboot"; \
	fi
	@if [ ! -f $(HOME)/.rboot/config.json ]; then \
	  echo '{}' > $(HOME)/.rboot/config.json; \
	  echo "Created: $(HOME)/.rboot/config.json"; \
	fi
	@case ":$$PATH:" in \
	  *":$(BIN_DIR):"*) echo "Run 'rboot' from inside any git repo." ;; \
	  *) echo "Warning: $(BIN_DIR) is not on your PATH." ; \
	     echo "Add to ~/.zshrc:  export PATH=\"$(BIN_DIR):$$PATH\"" ;; \
	esac

uninstall:
	rm -f $(LINK)
	@echo "Removed: $(LINK)"
