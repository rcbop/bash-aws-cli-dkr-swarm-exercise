FROM alpine:3.6

RUN	apk --update add \
		bash \
		ca-certificates \
		git \
		less=487-r0 \
		openssl \
		openssh-client \
		p7zip \
		python \
		py-lxml \
		py-pip \
		rsync \
		sshpass \
		sudo \
		vim \
		zip \
		file \
		# seq, sort, tee
		coreutils \
    	jq \
		# uuidgen
		util-linux \ 
  	&& apk add \
    	dos2unix \
			--update-cache \
			--repository http://dl-3.alpinelinux.org/alpine/edge/community/ \
			--allow-untrusted \
  	&& apk --update add --virtual \
		build-dependencies \
		python-dev \
		libffi-dev \
		openssl-dev \
		build-base \
	&& pip install --upgrade \
		pip \
		cffi \
	&& pip install \
		ansible==2.4.1 \
		ansible-lint==3.4.17 \
		awscli==1.11.85 \
		boto==2.45.0 \
		boto3==1.4.4 \
		docker-py==1.10.6 \
		dopy==0.3.7 \
		python_jenkins==0.4.15 \
		pywinrm>=0.1.1 \
		pyvmomi==6.0.0.2016.6 \
		pysphere>=0.1.7 \
	&& apk del build-dependencies \
	&& rm -rf /var/cache/apk/*
RUN apk add --no-cache tini tree

RUN	mkdir -p /etc/ansible \		
	&& echo 'localhost' > /etc/ansible/hosts \		
	&& mkdir -p ~/.ssh && touch ~/.ssh/known_hosts \
	&& ansible -c local -m setup all > /dev/null \
	&& mkdir -p /app
ARG AWS_KEY_ID
ARG AWS_SECRET_KEY

ENV AWS_KEY_ID=${AWS_KEY_ID}
ENV AWS_SECRET_KEY=${AWS_SECRET_KEY}

WORKDIR /app
COPY . /app

ENTRYPOINT ["/sbin/tini", "--" ]
CMD [ "./create-ec2-swarm-cluster.sh" ]