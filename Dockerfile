FROM gliderlabs/alpine:latest
MAINTAINER Alexei Ledenev <alexei.led@gmail.com>

ENV HUGO_VERSION=0.16
RUN apk add --update wget ca-certificates && \
  wget https://github.com/spf13/hugo/releases/download/v${HUGO_VERSION}/hugo_${HUGO_VERSION}_linux-64bit.tgz && \
  tar xzf hugo_${HUGO_VERSION}_linux_amd64.tar.gz && \
  rm -r hugo_${HUGO_VERSION}_linux_amd64.tar.gz && \
  mv hugo_${HUGO_VERSION}_linux_amd64/hugo_${HUGO_VERSION}_linux_amd64 /usr/bin/hugo && \
  rm -r hugo_${HUGO_VERSION}_linux_amd64 && \
  apk del wget ca-certificates && \
  rm /var/cache/apk/*

RUN mkdir -p /src /output

COPY . /src/
COPY ./run.sh /run.sh

RUN chmod +x /run.sh

WORKDIR /src
CMD ["/run.sh"]

EXPOSE 1313
