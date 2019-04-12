FROM docker:18.09

# https://github.com/docker/docker/blob/master/project/PACKAGERS.md#runtime-dependencies
RUN set -eux; \
	apk add --no-cache \
		btrfs-progs \
		e2fsprogs \
		e2fsprogs-extra \
		iptables \
		xfsprogs \
		xz \
# pigz: https://github.com/moby/moby/pull/35697 (faster gzip implementation)
		pigz \
	; \
# only install zfs if it's available for the current architecture
# https://git.alpinelinux.org/cgit/aports/tree/main/zfs/APKBUILD?h=3.6-stable#n9 ("all !armhf !ppc64le" as of 2017-11-01)
# "apk info XYZ" exits with a zero exit code but no output when the package exists but not for this arch
	if zfs="$(apk info --no-cache --quiet zfs)" && [ -n "$zfs" ]; then \
		apk add --no-cache zfs; \
	fi

# TODO aufs-tools

# set up subuid/subgid so that "--userns-remap=default" works out-of-the-box
RUN set -x \
	&& addgroup -S dockremap \
	&& adduser -S -G dockremap dockremap \
	&& echo 'dockremap:165536:65536' >> /etc/subuid \
	&& echo 'dockremap:165536:65536' >> /etc/subgid

# https://github.com/docker/docker/tree/master/hack/dind
ENV DIND_COMMIT 37498f009d8bf25fbb6199e8ccd34bed84f2874b

RUN set -eux; \
	wget -O /usr/local/bin/dind "https://raw.githubusercontent.com/docker/docker/${DIND_COMMIT}/hack/dind"; \
	chmod +x /usr/local/bin/dind

COPY dockerd-entrypoint.sh /usr/local/bin/

VOLUME /var/lib/docker
EXPOSE 2375

# adding java
RUN apk update && apk upgrade && \
    apk add openjdk8 && \
    mkdir /tmp/tmprt && \
    cd /tmp/tmprt && \
    apk add zip && \
    unzip -q /usr/lib/jvm/default-jvm/jre/lib/rt.jar && \
    apk add zip && \
    zip -q -r /tmp/rt.zip . && \
    apk del zip && \
    cd /tmp && \
    mv rt.zip /usr/lib/jvm/default-jvm/jre/lib/rt.jar && \
    rm -rf /tmp/tmprt /var/cache/apk/* bin/jjs bin/keytool bin/orbd bin/pack200 bin/policytool \
          bin/rmid bin/rmiregistry bin/servertool bin/tnameserv bin/unpack200
# adding jenkins slave
ARG VERSION=3.28
ARG user=jenkins
ARG group=jenkins
ARG uid=1000
ARG gid=1000

ENV HOME /home/${user}

RUN addgroup -g ${gid} ${group}
RUN addgroup docker
RUN adduser -h $HOME -u ${uid} -G ${group} -G dockremap -G docker -G root -D ${user}

RUN apk --no-cache add shadow && usermod -aG docker jenkins && usermod -aG dockremap jenkins

RUN set -- dockerd \
		--host=unix:///var/run/docker.sock \
		--host=tcp://0.0.0.0:2375

ARG AGENT_WORKDIR=/home/${user}/agent

RUN apk add --update --no-cache curl bash git openssh-client openssl procps \
  && curl --create-dirs -sSLo /usr/share/jenkins/slave.jar https://repo.jenkins-ci.org/public/org/jenkins-ci/main/remoting/${VERSION}/remoting-${VERSION}.jar \
  && chmod 755 /usr/share/jenkins \
  && chmod 644 /usr/share/jenkins/slave.jar \
  && apk del curl
USER ${user}
ENV AGENT_WORKDIR=${AGENT_WORKDIR}
RUN mkdir /home/${user}/.jenkins && mkdir -p ${AGENT_WORKDIR}

VOLUME /home/${user}/.jenkins
VOLUME ${AGENT_WORKDIR}
WORKDIR /home/${user}


COPY jenkins-slave /usr/local/bin/jenkins-slave
COPY wrapper.sh /usr/local/bin/wrapper.sh

ENTRYPOINT ["/usr/local/bin/wrapper.sh"]
CMD []