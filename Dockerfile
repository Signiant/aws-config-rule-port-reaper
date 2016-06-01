FROM alpine:latest

RUN \
	mkdir -p /aws && \
	apk -Uuv add bash groff less python py-pip && \
	pip install awscli && \
	apk --purge -v del py-pip && \
	rm /var/cache/apk/*

RUN mkdir /src

COPY src/ /src/

WORKDIR /src

ENTRYPOINT ["./run.sh"]
