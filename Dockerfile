# Estágio 1: Build do Flutter
FROM debian:latest AS build-env

# Instala dependências básicas
RUN apt-get update && apt-get install -y curl git wget unzip libgconf-2-4 gdb libstdc++6 libglu1-mesa fonts-droid-fallback python3 xz-utils
RUN apt-get clean

# Baixa o Flutter SDK (Versão Stable)
RUN git clone https://github.com/flutter/flutter.git -b stable /usr/local/flutter

# Adiciona o Flutter ao PATH
ENV PATH="/usr/local/flutter/bin:/usr/local/flutter/bin/cache/dart-sdk/bin:${PATH}"

# Roda o check e habilita web
RUN flutter doctor -v
RUN flutter config --enable-web

# Copia os arquivos do projeto e builda
WORKDIR /app
COPY . .
RUN flutter pub get
RUN flutter build web --release

# Estágio 2: Servidor leve para entregar o site (Nginx)
FROM nginx:alpine
COPY --from=build-env /app/build/web /usr/share/nginx/html

# Expõe a porta 80
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]