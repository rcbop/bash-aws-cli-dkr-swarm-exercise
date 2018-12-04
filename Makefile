copy:
	bash $(CURDIR)/utils/copy-templates.sh
create: copy
	bash $(CURDIR)/create-ec2-swarm-cluster.sh
clean:
	rm -rf $(CURDIR)/password.properties
	rm -rf $(CURDIR)/aws-variables.properties
build: copy
	bash $(CURDIR)/docker/docker-build.sh
dkrun:
	bash $(CURDIR)/docker/docker-run.sh
	
.PHONY: create clean build copy dkrun