# Estágio 1: Build do Flutter
FROM debian:bookworm-slim AS build-env

# Instala dependências básicas atualizadas (sem o libgconf-2-4)
RUN apt-get update && apt-get install -y \
    curl git wget unzip gdb libstdc++6 libglu1-mesa \
    fonts-droid-fallback python3 xz-utils \
    && apt-get clean

# Baixa o Flutter SDK
RUN git clone https://github.com/flutter/flutter.git -b stable /usr/local/flutter
ENV PATH="/usr/local/flutter/bin:/usr/local/flutter/bin/cache/dart-sdk/bin:${PATH}"

RUN flutter config --enable-web

WORKDIR /app
COPY . .

# Entra na pasta do projeto e compila
RUN cd $(dirname $(find . -name pubspec.yaml -print -quit)) && \
    flutter pub get && \
    flutter build web --release --no-pub

# Estágio 2: Nginx
FROM nginx:alpine
RUN rm -rf /usr/share/nginx/html/*
COPY --from=build-env /app/**/build/web /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]