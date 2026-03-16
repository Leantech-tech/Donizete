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

# Comando que busca o pubspec.yaml e faz o build onde quer que ele esteja
RUN find . -name "pubspec.yaml" -execdir flutter pub get \; \
    && find . -name "pubspec.yaml" -execdir flutter build web --release \;

# Estágio de Servidor (Nginx)
FROM nginx:alpine
RUN rm -rf /usr/share/nginx/html/*

# Busca a pasta build/web gerada e move o CONTEÚDO para a raiz do Nginx
RUN mkdir -p /temp_build
COPY --from=build-env /app /temp_build
RUN find /temp_build -type d -name "web" -path "*/build/web" -exec cp -r {}/. /usr/share/nginx/html/ \;

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]