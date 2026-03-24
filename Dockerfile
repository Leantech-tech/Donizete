# Estágio de Build
FROM debian:bookworm-slim AS build-env

RUN apt-get update && apt-get install -y \
    curl git wget unzip gdb libstdc++6 libglu1-mesa \
    fonts-droid-fallback python3 xz-utils \
    && apt-get clean

RUN git clone https://github.com/flutter/flutter.git -b stable /usr/local/flutter
ENV PATH="/usr/local/flutter/bin:/usr/local/flutter/bin/cache/dart-sdk/bin:${PATH}"

RUN flutter config --enable-web

WORKDIR /app
COPY . .

# Roda o build (gera a pasta build/web)
RUN flutter pub get && flutter build web --release

# Estágio de Servidor
FROM nginx:alpine
RUN rm -rf /usr/share/nginx/html/*

# Copia o conteúdo da pasta gerada para a pasta padrão do Nginx
COPY --from=build-env /app/build/web /usr/share/nginx/html

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
