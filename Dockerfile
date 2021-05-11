FROM maven:3.6.1-jdk-8 AS build
COPY src /usr/src/app/src
COPY pom.xml /usr/src/app/pom.xml
RUN mvn -f /usr/src/app/pom.xml dependency:resolve
RUN mvn -f /usr/src/app/pom.xml clean package

FROM jetty:9-jre8-alpine
COPY --from=build /usr/src/app/target/plan-net.war /var/lib/jetty/webapps/plan-net.war
COPY --from=build /usr/src/app/target /var/lib/jetty/target 
USER root
RUN apk add --update \
    curl \
    ruby-dev \
    && rm -rf /var/cache/apk/*
RUN gem install rdoc --no-document
RUN gem install zip
RUN gem install httparty
RUN chown -R jetty:jetty /var/lib/jetty/target
USER jetty:jetty
EXPOSE 8080
