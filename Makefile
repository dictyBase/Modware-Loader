VERSION = $(shell grep -E ^version dist.ini | cut -d'=' -f2 | sed -e 's/^[ \t]*//')
API_JSON = $(shell printf '{"tag_name": "%s","target_commitish": "develop","name": "%s","body": "Release of version %s","draft": false,"prerelease" : false}'  $(VERSION) $(VERSION) $(VERSION))
ACCESS_TOKEN = $(shell cat ~/.github-release)
NAME = Modware-Loader-$(VERSION).tar.gz
UPLOAD_URL = $(shell curl --silent --data '$(API_JSON)' https://api.github.com/repos/dictyBase/Modware-Loader/releases?access_token=$(ACCESS_TOKEN) | jq '.upload_url' | sed -e 's/{.*}//' | sed -e 's/"//g' | sed -e 's/[[:blank:]]*$$//') 
UPLOAD_URL += ?name=$(NAME)
ASSET_URL += $(shell echo $(UPLOAD_URL) | sed 's/[[:blank:]]//')

default: build test
#upload_url = $(shell curl --silent --data '$(api_json)' https://api.github.com/repos/dictybase/modware-loader/releases/latest?access_token=$(access_token) | jq '.upload_url' | sed -e 's/{.*}//' | sed -e 's/"//g' | sed -e 's/[[:blank:]]*$$//') 
build:
	docker build --rm --build-arg user=$(shell id -nu) curruid=$(shell id -u) -t dictybase/modware-loader-test:devel .
test:
	docker run --rm -v $(shell pwd):/usr/src/modware -e HARNESS_OPTIONS="j6" dictybase/modware-loader-test:devel
testpg: 
	docker run -d --name mlpostgres -e ADMIN_DB=mldb -e ADMIN_USER=mluser -e ADMIN_PASS=mlpass dictybase/postgres:9.4 \
		&& sleep 10 \
		&& docker run --rm -v $(shell pwd):/usr/src/modware --link mlpostgres:ml -e TC_DSN="dbi:Pg:database=mldb;host=ml" -e TC_USER=mluser \
		-e TC_PASS=mlpass -e HARNESS_OPTIONS="j6" dictybase/modware-loader-test:devel \
			&& docker stop mlpostgres \
			&& docker rm mlpostgres
release: build test testpg
	docker run --rm -v $(pwd):/usr/src/modware dictybase/modware-loader-test:devel /bin/bash -c "dzil clean && dzil build"
	git add Build.PL README.md dist.ini
	git add META.JSON
	git commit -m 'bumped version and toolchain files for version $(VERSION)'
release-only: 
	docker run --rm -v $(PWD):/usr/src/modware dictybase/modware-loader-test:devel /bin/bash -c "dzil clean && dzil build"
	git add Build.PL README.md dist.ini
	git add META.JSON
	git commit -m 'bumped version and toolchain files for version $(VERSION)'
create-dockerfile:
	cp $(PWD)/docker/template/Dockerfile $(PWD)/docker/release/Dockerfile
	sed -i -e 's/version/$(VERSION)/' $(PWD)/docker/release/Dockerfile
	git add $(PWD)/docker/release
	git commit -m 'updated dockerfile for this $(VERSION)'
gh-release: create-dockerfile 
	git checkout master
	git rebase develop
	git push origin master
	git checkout develop
	git push origin develop
	curl -X POST -H 'Content-Type: application/gzip' -H 'Authorization: token $(ACCESS_TOKEN)' --data-binary @$(NAME) $(ASSET_URL)
gh-release-only:
	git checkout master
	git rebase develop
	git push origin master
	git checkout develop
	git push origin develop
	curl -X POST -H 'Content-Type: application/gzip' -H 'Authorization: token $(ACCESS_TOKEN)' --data-binary @$(NAME) $(ASSET_URL)

