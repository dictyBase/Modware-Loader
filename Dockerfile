FROM perl:5.20
MAINTAINER Siddhartha Basu <siddhartha-basu@northwestern.edu>

ADD https://northwestern.box.com/shared/static/3n0wdp04075oyrnytznn9mzc3k9o92c1.rpm /rpms/
ADD https://northwestern.box.com/shared/static/o2gd3o70sik5liw43hiomusmu0262auw.rpm /rpms/
ADD https://northwestern.box.com/shared/static/nsflzsbm2xmcf46z1ybiustosqkdskbb.rpm /rpms/

RUN apt-get update && \
    apt-get -y install alien libaio1 libdb-dev libexpat1-dev && \
    mkdir -p /rpms && \
    alien -i /rpms/*.rpm && \
    echo '/usr/lib/oracle/11.2/client64/lib' > /etc/ld.so.conf.d/oracle.conf && \
    echo 'export ORACLE_HOME=/usr/lib/oracle/11.2/client64' > /etc/profile.d/oracle.sh

ENV ORACLE_HOME /usr/lib/oracle/11.2/client64/
ENV LD_LIBRARY_PATH /usr/lib/oracle/11.2/client64/lib/

ADD cpanfile /tmp/
RUN cd /tmp \
    && cpanm -n --quiet --installdeps . \
    && cpanm -n --quiet DBD::Oracle DBD::Pg Math::Base36 String::CamelCase LWP::Protocol::https && \
    rm -fr /rpms
RUN cpanm -n --quiet Child Dist::Zilla

COPY bin /usr/src/modware/bin
COPY lib /usr/src/modware/lib
COPY t /usr/src/modware/t
COPY share /usr/src/modware/share
COPY Build.PL /usr/src/modware/
COPY Changes /usr/src/modware/
COPY MANIFEST.SKIP /usr/src/modware/
COPY META.json /usr/src/modware/
COPY MYMETA.json /usr/src/modware/
COPY MYMETA.yml /usr/src/modware/
COPY dist.ini /usr/src/modware/
WORKDIR /usr/src/modware
RUN dzil authordeps | cpanm -n --quiet \
    && perl Build.PL && ./Build install
