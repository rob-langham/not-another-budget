# Build: docker build -t longview-backend backend/
FROM gradle:8.14.3-jdk21 AS build
WORKDIR /src
COPY . .
RUN gradle installDist --no-daemon -q

FROM eclipse-temurin:21-jre
WORKDIR /app
COPY --from=build /src/build/install/longview-backend /app
ENV DB_PATH=/data/longview.db PORT=8080
VOLUME /data
EXPOSE 8080
CMD ["/app/bin/longview-backend"]
