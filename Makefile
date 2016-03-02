VERSION=$(shell grep -E ^version dist.ini | cut -d'=' -f2 | sed -e 's/^[ \t]*//')
API_JSON=$(shell printf '{"tag_name": "%s","target_commitish": "develop","name": "%s","body": "Release of version %s","draft": false,"prerelease" : false}'  $(VERSION) $(VERSION) $(VERSION))
ACCESS_TOKEN=$(shell cat ~/.github-release)
default: build test
build:
	docker build --rm -t dictybase/modware-loader-test:devel .
test:
	docker run --rm -v $(PWD):/usr/src/modware dictybase/modware-loader-test:devel
testpg: build
	docker run -d --name mlpostgres -e ADMIN_DB=mldb -e ADMIN_USER=mluser -e ADMIN_PASS=mlpass dictybase/postgres:9.4 \
		&& sleep 10 \
		&& docker run --rm -v $(PWD):/usr/src/modware --link mlpostgres:ml -e TC_DSN="dbi:Pg:dbname=mldb;host=ml" -e TC_USER=mluser \
		-e TC_PASS=mlpass dictybase/modware-loader-test:devel \
			&& docker stop mlpostgres \
			&& docker rm mlpostgres
release: build test testpg
	docker run --rm -v $(PWD):/usr/src/modware dictybase/modware-loader-test:devel dzil clean
	docker run --rm -v $(PWD):/usr/src/modware dictybase/modware-loader-test:devel dzil build
	git add Build.PL META.JSON README.md dist.ini
	git commit -m 'bumped version and toolchain files for version $(VERSION)'
release-only: 
	docker run --rm -v $(PWD):/usr/src/modware dictybase/modware-loader-test:devel dzil clean
	docker run --rm -v $(PWD):/usr/src/modware dictybase/modware-loader-test:devel dzil build
	git add Build.PL META.JSON README.md dist.ini
	git commit -m 'bumped version and toolchain files for version $(VERSION)'
create-dockerfile:
	cp $(PWD)/docker/template/Dockerfile $(PWD)/docker/release/Dockerfile
	sed -i -e 's/release/$(VERSION)' $(PWD)/docker/release/Dockerfile
	git add $(PWD)/docker/release
	git commit -m 'updated dockerfile for this $(VERSION)'
gh-release: release-only create-dockerfile 
	git push github develop
	UPLOAD_URL=$(shell curl --silent --data '$(API_JSON)' https://api.github.com/repos/dictyBase/Modware-Loader/releases?access_token=$(ACCESS_TOKEN) | jq '.upload_url' | sed -e 's/{.*}//') 
	name=$(shell Modware-Loader-$(VERSION).tar.gz)
	curl -X POST -H 'Content-Type: application/gzip' --data-binary @$(VERSION) $(UPLOAD_URL)?name=$(name)&access_token=$(ACCESS_TOKEN)
	


