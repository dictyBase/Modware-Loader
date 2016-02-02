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
	docker run --rm -v $(PWD):/usr/src/modware dictybase/modware-loader-test:devel dzil build

