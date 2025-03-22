build-HelloWorldFunction:
	cp -r . $(ARTIFACTS_DIR)
	pip install -r requirements.txt -t $(ARTIFACTS_DIR)
	rm -rf $(ARTIFACTS_DIR)/bin
	find $(ARTIFACTS_DIR) -type f -name '__editable__.*.pth' -exec sed -i 's|/tmp/tmp[^/]*/|/var/task/|g' {} \;
	rm -rf $(ARTIFACTS_DIR)/sam-sync-test-upstream
	ln -s /home/jeff/src/sam-sync-test/hello_world/sam-sync-test-upstream $(ARTIFACTS_DIR)/sam-sync-test-upstream
