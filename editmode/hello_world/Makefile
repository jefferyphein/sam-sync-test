build-HelloWorldFunction:
	cp *.py $(ARTIFACTS_DIR)
	pip install -r requirements.txt -t $(ARTIFACTS_DIR)
	rm -rf $(ARTIFACTS_DIR)/bin
	find $(ARTIFACTS_DIR) -type f -name '__editable__.*.pth' -exec sed -i 's|/tmp/tmp[^/]*/|/var/task/|g' {} \;
	ln -s /home/jeff/src/sam-sync-test/editmode/hello_world/sam-sync-test-upstream $(ARTIFACTS_DIR)/sam-sync-test-upstream
