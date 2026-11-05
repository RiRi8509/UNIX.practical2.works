FROM alpine:3.22

RUN apk add --no-cache util-linux

COPY run.sh /usr/local/bin/run.sh

RUN chmod +x /usr/local/bin/run.sh

VOLUME ["/shared"]

ENTRYPOINT ["/usr/local/bin/run.sh"]
