# Estágio 1: Build
FROM debian:latest AS build-env

RUN apt-get update && apt-get install -y \
    curl git wget unzip libgconf-2-4 gdb libstdc++6 libglu1-mesa \
    fonts-droid-fallback python3 xz-utils \
    && apt-get clean

RUN git clone https://github.com/flutter/flutter.git -b stable /usr/local/flutter
ENV PATH="/usr/local/flutter/bin:/usr/local/flutter/bin/cache/dart-sdk/bin:${PATH}"

RUN flutter config --enable-web

WORKDIR /app
COPY . .

# ESTA LINHA É A CHAVE: Ela procura onde está o pubspec e entra na pasta automaticamente
RUN cd $(dirname $(find . -name pubspec.yaml -print -quit)) && \
    flutter pub get && \
    flutter build web --release --no-pub

# Estágio 2: Nginx
FROM nginx:alpine
RUN rm -rf /usr/share/nginx/html/*

# Busca o resultado do build onde quer que ele tenha sido gerado
COPY --from=build-env /app/**/build/web /usr/share/nginx/html

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]