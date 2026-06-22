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
	@case ":$$PATH:" in \
	  *":$(BIN_DIR):"*) echo "Run 'rboot' from inside any git repo." ;; \
	  *) echo "Warning: $(BIN_DIR) is not on your PATH." ; \
	     echo "Add to ~/.zshrc:  export PATH=\"$(BIN_DIR):$$PATH\"" ;; \
	esac

uninstall:
	rm -f $(LINK)
	@echo "Removed: $(LINK)"
