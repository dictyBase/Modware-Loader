FROM perl:5.32
MAINTAINER Siddhartha Basu <siddhartha-basu@northwestern.edu>

ADD oracle/*rpm /rpms/

RUN apt-get update && \
    apt-get -y install alien libaio1 libdb-dev && \
    mkdir -p /rpms && \
    alien -i /rpms/*.rpm && \
    echo '/usr/lib/oracle/11.2/client64/lib' > /etc/ld.so.conf.d/oracle.conf && \
    echo 'export ORACLE_HOME=/usr/lib/oracle/11.2/client64' > /etc/profile.d/oracle.sh \
    && apt-get clean \
    && apt-get autoremove \
    && rm -rf /var/lib/apt/lists/*

ENV ORACLE_HOME /usr/lib/oracle/11.2/client64/
ENV LD_LIBRARY_PATH /usr/lib/oracle/11.2/client64/lib/
RUN cpanm -n --quiet DBI DBD::Oracle  DBD::Pg Math::Base36 String::CamelCase Child JSON \
    && rm -fr /rpms
RUN cpanm -n --quiet https://github.com/dictyBase/Modware-Loader.git@v1.10.5
CMD ['modware']
